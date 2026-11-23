// ===========================================================================
//  Ember Bridge — ESP32 firmware
//
//  Sits in the car, listens for the Ember iPhone app over Bluetooth LE, and
//  pulses relay outputs wired to an aftermarket remote-start module
//  (e.g. a Fortin EVO-ONE on a 2019–2022 Mazda3 push-to-start).
//
//  Security, two layers:
//    1. BLE pairing with a 6-digit passkey (encrypted, bonded link).
//    2. Every command carries an HMAC-SHA256 over a one-time challenge,
//       keyed with a 32-byte secret only the bridge and your phone know.
//       A pairing alone cannot send commands, and recorded commands
//       cannot be replayed.
//
//  Requires:  Arduino-ESP32 core (2.x or 3.x) + library "NimBLE-Arduino" 2.x
//  Board:     any ESP32 dev board (ESP32-WROOM-32 tested target)
// ===========================================================================

#include <NimBLEDevice.h>
#include "mbedtls/md.h"
#include "esp_random.h"
#include "driver/twai.h"
#include "config.h"

// ---- Protocol (must match CarProtocol.swift) ------------------------------
static const char* SERVICE_UUID   = "e1ff55ff-6a97-433b-bea8-9ec4b34f384e";
static const char* CHALLENGE_UUID = "19761279-973c-47a5-8d3d-08d03f22677c";
static const char* COMMAND_UUID   = "6a4d6a66-0fe9-48ca-878e-238060417a9d";
static const char* STATUS_UUID    = "7bdb2e96-9fcf-4522-b098-7264afa1c44d";
static const char* VEHICLE_UUID   = "c8877ecc-75f8-4914-a91b-f18cdebf0910";

enum Command : uint8_t {
  CMD_LOCK   = 0x01,
  CMD_UNLOCK = 0x02,
  CMD_START  = 0x03,
  CMD_STOP   = 0x04,
  CMD_AUX1   = 0x05,
};

enum Result : uint8_t {
  RES_NONE            = 0,
  RES_OK              = 1,
  RES_BAD_AUTH        = 2,
  RES_ALREADY_RUNNING = 3,
  RES_NOT_RUNNING     = 4,
  RES_LOCKED_OUT      = 5,
  RES_BAD_FORMAT      = 6,
  RES_UNSUPPORTED     = 7,
};

// Status flags (byte 1 of the status packet)
static const uint8_t FLAG_RUNNING      = 0x01;
static const uint8_t FLAG_RUN_WIRED    = 0x02;
static const uint8_t FLAG_LOCK_KNOWN   = 0x04;
static const uint8_t FLAG_LOCKED       = 0x08;

static const size_t NONCE_LEN = 16;
static const size_t MAC_LEN   = 16;   // truncated HMAC-SHA256
static const uint8_t DOMAIN[4] = {'E', 'M', 'B', 'R'};

// ---- State ----------------------------------------------------------------
struct QueuedCommand { uint8_t cmd; uint8_t preResult; };  // preResult != RES_NONE => reject without acting

static uint8_t  secretKey[32];
static uint8_t  nonce[NONCE_LEN];
static QueueHandle_t cmdQueue;

static NimBLECharacteristic* challengeChar = nullptr;
static NimBLECharacteristic* statusChar    = nullptr;
static NimBLECharacteristic* vehicleChar   = nullptr;

static volatile uint8_t  badAuthCount = 0;
static volatile uint32_t lockoutUntilMs = 0;

static bool     engineRunning   = false;
static uint32_t runStartedMs    = 0;
static bool     runStartKnown   = false;  // false if engine was already running when we booted/noticed it
static bool     lockKnown       = false;
static bool     locked          = false;
static uint8_t  lastResult      = RES_NONE;
static uint8_t  commandSeq      = 0;
static uint8_t  lastStatusSent[6] = {0};

// ---- Helpers --------------------------------------------------------------
static int hexNibble(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

static bool parseSecret(const char* hex, uint8_t* out) {
  if (strlen(hex) != 64) return false;
  for (int i = 0; i < 32; i++) {
    int hi = hexNibble(hex[2 * i]), lo = hexNibble(hex[2 * i + 1]);
    if (hi < 0 || lo < 0) return false;
    out[i] = (uint8_t)((hi << 4) | lo);
  }
  return true;
}

static void newChallenge() {
  esp_fill_random(nonce, NONCE_LEN);
  if (challengeChar) challengeChar->setValue(nonce, NONCE_LEN);
}

// MAC = first 16 bytes of HMAC-SHA256(secret, "EMBR" || nonce || cmd)
static bool computeMac(uint8_t cmd, const uint8_t* forNonce, uint8_t* macOut) {
  uint8_t msg[sizeof(DOMAIN) + NONCE_LEN + 1];
  memcpy(msg, DOMAIN, sizeof(DOMAIN));
  memcpy(msg + sizeof(DOMAIN), forNonce, NONCE_LEN);
  msg[sizeof(DOMAIN) + NONCE_LEN] = cmd;
  uint8_t full[32];
  const mbedtls_md_info_t* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  if (mbedtls_md_hmac(info, secretKey, sizeof(secretKey), msg, sizeof(msg), full) != 0) return false;
  memcpy(macOut, full, MAC_LEN);
  return true;
}

static bool constantTimeEqual(const uint8_t* a, const uint8_t* b, size_t n) {
  uint8_t diff = 0;
  for (size_t i = 0; i < n; i++) diff |= a[i] ^ b[i];
  return diff == 0;
}

static void setOutputIdle(int pin) {
  if (pin < 0) return;
  digitalWrite(pin, OUTPUT_ACTIVE_LEVEL == LOW ? HIGH : LOW);  // set level BEFORE enabling output: no boot glitch
  pinMode(pin, OUTPUT);
}

static void pulse(int pin) {
  if (pin < 0) return;
  digitalWrite(pin, OUTPUT_ACTIVE_LEVEL);
  delay(PULSE_MS);
  digitalWrite(pin, OUTPUT_ACTIVE_LEVEL == LOW ? HIGH : LOW);
}

static bool runStatusWired() { return PIN_RUN_STATUS >= 0; }

static uint32_t runTimeMs() { return (uint32_t)RUN_TIME_MINUTES * 60UL * 1000UL; }

static const uint32_t START_GRACE_MS = 20000;  // time allowed for the module to crank and report "running"

// True for a short window after we sent START and the engine hasn't reported running yet.
static bool startInProgress() {
  return runStartKnown && !engineRunning && (millis() - runStartedMs < START_GRACE_MS);
}

// Refresh engineRunning from the status input, or from our own timer.
static void updateEngineState() {
  uint32_t now = millis();
  if (runStatusWired()) {
    bool running = digitalRead(PIN_RUN_STATUS) == RUN_STATUS_ACTIVE_LEVEL;
    if (running && !engineRunning) {
      // Became running. If we didn't just start it (fob start, or running at boot),
      // we don't know the real start time, so no countdown.
      if (!startInProgress()) { runStartKnown = false; runStartedMs = now; }
    } else if (!running && engineRunning) {
      runStartKnown = false;                                   // engine stopped
    } else if (!running && runStartKnown && !startInProgress()) {
      runStartKnown = false;                                   // our start never took
    }
    engineRunning = running;
  } else {
    if (engineRunning && now - runStartedMs >= runTimeMs()) engineRunning = false;
  }
}

static uint16_t secondsRemaining() {
  if (!engineRunning || !runStartKnown) return 0;
  uint32_t elapsed = millis() - runStartedMs;
  if (elapsed >= runTimeMs()) return 0;
  return (uint16_t)((runTimeMs() - elapsed) / 1000UL);
}

// Status packet: [ver=1][flags][secsRemaining LE16][lastResult][commandSeq]
static void buildStatus(uint8_t* p) {
  uint8_t flags = 0;
  if (engineRunning)    flags |= FLAG_RUNNING;
  if (runStatusWired()) flags |= FLAG_RUN_WIRED;
  if (lockKnown)        flags |= FLAG_LOCK_KNOWN;
  if (locked)           flags |= FLAG_LOCKED;
  uint16_t secs = secondsRemaining();
  p[0] = 1;
  p[1] = flags;
  p[2] = secs & 0xFF;
  p[3] = secs >> 8;
  p[4] = lastResult;
  p[5] = commandSeq;
}

static void publishStatus(bool force) {
  uint8_t p[6];
  buildStatus(p);
  if (!force && memcmp(p, lastStatusSent, sizeof(p)) == 0) return;
  memcpy(lastStatusSent, p, sizeof(p));
  statusChar->setValue(p, sizeof(p));
  if (NimBLEDevice::getServer()->getConnectedCount() > 0) statusChar->notify();
}


// ---- Vehicle info: fuel level over OBD-II (read-only) ---------------------
//  Vehicle packet (must match CarProtocol.swift):
//  [ver=1][flags][fuel %][fuel age min LE16][FL FR RL RR tire psi*10 LE16 each][tire age min LE16]
//  flags: bit0 fuel known, bit1 tires known. "Unknown" values are 0xFFFF.
static const uint8_t VFLAG_FUEL  = 0x01;
static const uint8_t VFLAG_TIRES = 0x02;
static const size_t  VEHICLE_LEN = 15;

static int16_t  fuelPercent    = -1;      // -1 = no reading yet
static uint32_t fuelReadMs     = 0;
static uint32_t lastBusFrameMs = 0;       // last time we saw ANY traffic from the car
static uint32_t lastFuelAskMs  = 0;
static bool     obdReady       = false;
static uint8_t  lastVehicleSent[VEHICLE_LEN] = {0};

static uint16_t minutesSince(uint32_t ms) {
  uint32_t m = (millis() - ms) / 60000UL;
  return m > 0xFFFE ? 0xFFFE : (uint16_t)m;
}

static void buildVehicle(uint8_t* p) {
  memset(p, 0xFF, VEHICLE_LEN);
  p[0] = 1;
  p[1] = 0;
  p[2] = 0;
  if (fuelPercent >= 0) {
    p[1] |= VFLAG_FUEL;
    p[2] = (uint8_t)fuelPercent;
    uint16_t age = minutesSince(fuelReadMs);
    p[3] = age & 0xFF; p[4] = age >> 8;
  }
  // Tire pressures (p[5..12], p[13..14]) stay 0xFFFF until the Mazda-specific
  // request for them is known. The app shows "not set up yet" in that case.
}

static void publishVehicle(bool force) {
  if (!vehicleChar) return;
  uint8_t p[VEHICLE_LEN];
  buildVehicle(p);
  if (!force && memcmp(p, lastVehicleSent, VEHICLE_LEN) == 0) return;
  memcpy(lastVehicleSent, p, VEHICLE_LEN);
  vehicleChar->setValue(p, VEHICLE_LEN);
  if (NimBLEDevice::getServer()->getConnectedCount() > 0) vehicleChar->notify();
}

// Decode one received CAN frame. Returns true if it was a fuel-level answer.
// OBD-II answer to "mode 01, PID 2F": ID 0x7E8..0x7EF, data [len][0x41][0x2F][A] -> A*100/255 %
static bool handleObdFrame(uint32_t id, const uint8_t* d, uint8_t len) {
  lastBusFrameMs = millis();
  if (id < 0x7E8 || id > 0x7EF || len < 4) return false;
  if (d[1] != 0x41 || d[2] != 0x2F) return false;
  fuelPercent = (int16_t)((d[3] * 100 + 127) / 255);
  fuelReadMs = millis();
  return true;
}

static bool carAwake() {
  // Ask only while the car is clearly on: engine running, or the car's own
  // modules are already talking. Never wakes a parked car.
  return engineRunning || (lastBusFrameMs != 0 && millis() - lastBusFrameMs < 3000);
}

static void obdSetup() {
#if OBD_ENABLED
  twai_general_config_t g = TWAI_GENERAL_CONFIG_DEFAULT((gpio_num_t)PIN_CAN_TX, (gpio_num_t)PIN_CAN_RX, TWAI_MODE_NORMAL);
  g.tx_queue_len = 2;
  g.rx_queue_len = 16;
  twai_timing_config_t t = TWAI_TIMING_CONFIG_500KBITS();   // OBD-II on CAN (ISO 15765-4) runs at 500 kbit/s
  twai_filter_config_t f = TWAI_FILTER_CONFIG_ACCEPT_ALL();
  if (twai_driver_install(&g, &t, &f) == ESP_OK && twai_start() == ESP_OK) {
    obdReady = true;
    Serial.println("OBD-II reader ready");
  } else {
    Serial.println("OBD-II reader failed to start (check transceiver wiring)");
  }
#endif
}

static void obdLoop() {
#if OBD_ENABLED
  if (!obdReady) return;
  twai_message_t m;
  while (twai_receive(&m, 0) == ESP_OK) {
    if (!m.extd && !m.rtr && handleObdFrame(m.identifier, m.data, m.data_length_code)) {
      publishVehicle(true);
    }
  }
  twai_status_info_t st;
  if (twai_get_status_info(&st) == ESP_OK) {
    if (st.state == TWAI_STATE_BUS_OFF) { twai_initiate_recovery(); return; }  // e.g. asked while nothing answered
    if (st.state == TWAI_STATE_STOPPED) { twai_start(); return; }              // recovery finished
  }
  if (carAwake() && millis() - lastFuelAskMs >= (uint32_t)FUEL_POLL_SECONDS * 1000UL) {
    lastFuelAskMs = millis();
    twai_message_t q = {};
    q.identifier = 0x7DF;                 // OBD-II functional "anyone who knows" request
    q.data_length_code = 8;
    const uint8_t req[8] = {0x02, 0x01, 0x2F, 0x55, 0x55, 0x55, 0x55, 0x55};
    memcpy(q.data, req, 8);
    twai_transmit(&q, 0);
  }
#endif
}

// ---- Command execution (runs in loop(), never inside a BLE callback) ------
static uint8_t execute(uint8_t cmd) {
  updateEngineState();
  switch (cmd) {
    case CMD_LOCK:
      if (PIN_LOCK < 0) return RES_UNSUPPORTED;
      pulse(PIN_LOCK);
      lockKnown = true; locked = true;
      return RES_OK;

    case CMD_UNLOCK:
      if (PIN_UNLOCK < 0) return RES_UNSUPPORTED;
      pulse(PIN_UNLOCK);
      lockKnown = true; locked = false;
      return RES_OK;

    case CMD_START:
      if (PIN_START < 0) return RES_UNSUPPORTED;
      // A second pulse would STOP a toggling module, so refuse while running or cranking.
      if (engineRunning || (runStatusWired() && startInProgress())) return RES_ALREADY_RUNNING;
      pulse(PIN_START);
      runStartedMs = millis();
      runStartKnown = true;
      if (!runStatusWired()) engineRunning = true;     // no feedback: assume it started
      return RES_OK;

    case CMD_STOP: {
      if (!engineRunning) return RES_NOT_RUNNING;
      int pin = PIN_STOP >= 0 ? PIN_STOP : PIN_START;  // toggle on START input if no dedicated STOP
      if (pin < 0) return RES_UNSUPPORTED;
      pulse(pin);
      if (!runStatusWired()) engineRunning = false;
      runStartKnown = false;
      return RES_OK;
    }

    case CMD_AUX1:
      if (PIN_AUX1 < 0) return RES_UNSUPPORTED;
      if (!engineRunning) return RES_NOT_RUNNING;
      pulse(PIN_AUX1);
      return RES_OK;

    default:
      return RES_BAD_FORMAT;
  }
}

// ---- BLE callbacks ---------------------------------------------------------
class CommandCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& connInfo) override {
    QueuedCommand q = {0, RES_NONE};
    NimBLEAttValue v = c->getValue();

    if (!connInfo.isEncrypted() || !connInfo.isAuthenticated()) {
      q.preResult = RES_BAD_AUTH;
    } else if ((int32_t)(lockoutUntilMs - millis()) > 0) {
      q.preResult = RES_LOCKED_OUT;
    } else if (v.size() != 1 + MAC_LEN) {
      q.preResult = RES_BAD_FORMAT;
    } else {
      q.cmd = v.data()[0];
      uint8_t expected[MAC_LEN];
      bool ok = computeMac(q.cmd, nonce, expected) &&
                constantTimeEqual(expected, v.data() + 1, MAC_LEN);
      if (ok) {
        badAuthCount = 0;
      } else {
        q.preResult = RES_BAD_AUTH;
        if (++badAuthCount >= MAX_BAD_AUTH) {
          badAuthCount = 0;
          lockoutUntilMs = millis() + LOCKOUT_SECONDS * 1000UL;
        }
      }
    }

    newChallenge();  // every challenge is single-use, success or not
    xQueueSend(cmdQueue, &q, 0);
  }
};

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* s, NimBLEConnInfo& connInfo) override {
    newChallenge();
    Serial.printf("Connected: %s\n", connInfo.getAddress().toString().c_str());
  }
  void onDisconnect(NimBLEServer* s, NimBLEConnInfo& connInfo, int reason) override {
    Serial.printf("Disconnected (reason %d)\n", reason);
    newChallenge();
    NimBLEDevice::startAdvertising();
  }
  uint32_t onPassKeyDisplay() override {
    return EMBER_PASSKEY;
  }
  void onAuthenticationComplete(NimBLEConnInfo& connInfo) override {
    if (!connInfo.isEncrypted()) {
      Serial.println("Pairing failed — disconnecting");
      NimBLEDevice::getServer()->disconnect(connInfo.getConnHandle());
    } else {
      Serial.println("Link encrypted");
    }
  }
};

// ---- Setup / loop ----------------------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println("\nEmber Bridge starting");

  // Outputs idle first, before anything else can happen.
  setOutputIdle(PIN_LOCK);
  setOutputIdle(PIN_UNLOCK);
  setOutputIdle(PIN_START);
  setOutputIdle(PIN_STOP);
  setOutputIdle(PIN_AUX1);
  if (runStatusWired()) pinMode(PIN_RUN_STATUS, INPUT_PULLUP);

  if (!parseSecret(EMBER_SECRET_HEX, secretKey)) {
    Serial.println("ERROR: EMBER_SECRET_HEX in config.h is not 64 hex characters. Halting.");
    while (true) delay(1000);
  }
  if (EMBER_PASSKEY < 100000 || EMBER_PASSKEY > 999999) {
    Serial.println("ERROR: EMBER_PASSKEY must be 6 digits and not start with 0. Halting.");
    while (true) delay(1000);
  }
  if (EMBER_PASSKEY == 123456) {
    Serial.println("ERROR: EMBER_PASSKEY is still the example 123456. Pick your own in config.h. Halting.");
    while (true) delay(1000);
  }

  setCpuFrequencyMhz(80);  // saves power; BLE runs fine at 80 MHz

  cmdQueue = xQueueCreate(4, sizeof(QueuedCommand));

  NimBLEDevice::init(EMBER_DEVICE_NAME);
  NimBLEDevice::setSecurityAuth(true, true, true);          // bonding, MITM protection, LE Secure Connections
  NimBLEDevice::setSecurityPasskey(EMBER_PASSKEY);
  NimBLEDevice::setSecurityIOCap(BLE_HS_IO_DISPLAY_ONLY);   // phone enters the passkey

  NimBLEServer* server = NimBLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  NimBLEService* svc = server->createService(SERVICE_UUID);

  challengeChar = svc->createCharacteristic(
      CHALLENGE_UUID,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::READ_ENC | NIMBLE_PROPERTY::READ_AUTHEN);

  NimBLECharacteristic* commandChar = svc->createCharacteristic(
      COMMAND_UUID,
      NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_ENC | NIMBLE_PROPERTY::WRITE_AUTHEN);
  commandChar->setCallbacks(new CommandCallbacks());

  statusChar = svc->createCharacteristic(
      STATUS_UUID,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::READ_ENC | NIMBLE_PROPERTY::NOTIFY);

  vehicleChar = svc->createCharacteristic(
      VEHICLE_UUID,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::READ_ENC | NIMBLE_PROPERTY::NOTIFY);

  svc->start();
  newChallenge();
  obdSetup();
  publishVehicle(true);
  updateEngineState();
  publishStatus(true);

  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setName(EMBER_DEVICE_NAME);
  adv->enableScanResponse(true);
  adv->start();

  Serial.println("Advertising. Waiting for the app.");
}

void loop() {
  QueuedCommand q;
  if (xQueueReceive(cmdQueue, &q, pdMS_TO_TICKS(250)) == pdTRUE) {
    lastResult = (q.preResult != RES_NONE) ? q.preResult : execute(q.cmd);
    commandSeq++;
    Serial.printf("Command 0x%02X -> result %u\n", q.cmd, lastResult);
    updateEngineState();
    publishStatus(true);
  }

  obdLoop();

  static uint32_t lastTick = 0;
  if (millis() - lastTick >= 1000) {
    lastTick = millis();
    updateEngineState();
    publishStatus(false);  // only notifies when something changed (e.g. countdown)
    publishVehicle(false); // e.g. "updated N min ago" ticking over
  }
}
