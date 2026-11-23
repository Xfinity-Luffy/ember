// ===========================================================================
//  Ember Bridge — optional LTE + GPS (SIM7080G)
//
//  Included by EmberBridge.ino after its globals. Runs in its own FreeRTOS
//  task so slow modem work never delays Bluetooth or relay pulses.
//
//  Cycle:  [GPS fix] -> [cellular] -> POST signed report to the relay
//          -> receive queued commands -> verify -> hand them to loop()
//          -> results go back as "acks" in the next report.
//  The SIM7080G can't use GPS and LTE at the same time (they share radio
//  parts), so the task takes turns between them.
//
//  Security:
//   - Reports are signed: X-Ember-Sig = HMAC(key, "EMBR-RPT" || body)[0..16].
//   - Commands are signed end-to-end by the phone:
//       [cmd][unix time BE 4][nonce 8][HMAC(key, "EMBR-LTE"||cmd||time||nonce)[0..16]]
//     and accepted only within 5 minutes of the car's clock and only once.
//   - The relay only stores and forwards; it never sees the key.
// ===========================================================================
#pragma once

static const size_t LTE_PACKET_LEN = 29;
static const uint32_t LTE_MAX_SKEW = 300;   // seconds

// ---- Pure helpers (no hardware; unit-tested) ------------------------------

static void hmacTrunc(const char* label, const uint8_t* a, size_t aLen,
                      const uint8_t* b, size_t bLen, uint8_t* out, size_t outLen) {
  uint8_t msg[8 + 2100];
  size_t n = strlen(label);
  memcpy(msg, label, n);
  if (aLen) { memcpy(msg + n, a, aLen); n += aLen; }
  if (bLen) { memcpy(msg + n, b, bLen); n += bLen; }
  uint8_t full[32];
  const mbedtls_md_info_t* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  mbedtls_md_hmac(info, secretKey, sizeof(secretKey), msg, n, full);
  memcpy(out, full, outLen);
}

static void toHex(const uint8_t* in, size_t len, char* out) {
  static const char* d = "0123456789abcdef";
  for (size_t i = 0; i < len; i++) { out[2 * i] = d[in[i] >> 4]; out[2 * i + 1] = d[in[i] & 15]; }
  out[2 * len] = 0;
}

static bool fromHex(const char* in, uint8_t* out, size_t len) {
  for (size_t i = 0; i < len; i++) {
    int hi = hexNibble(in[2 * i]), lo = hexNibble(in[2 * i + 1]);
    if (hi < 0 || lo < 0) return false;
    out[i] = (uint8_t)((hi << 4) | lo);
  }
  return true;
}

// carId = first 8 bytes of HMAC(key,"EMBR-ID"); token = first 16 of HMAC(key,"EMBR-API").
static void deriveIds(char* carIdHex, char* tokenHex) {
  uint8_t b[16];
  hmacTrunc("EMBR-ID", nullptr, 0, nullptr, 0, b, 8);   toHex(b, 8, carIdHex);
  hmacTrunc("EMBR-API", nullptr, 0, nullptr, 0, b, 16); toHex(b, 16, tokenHex);
}

// Days since 1970-01-01 for a civil date (Howard Hinnant's algorithm).
static int64_t daysFromCivil(int y, unsigned m, unsigned d) {
  y -= m <= 2;
  const int64_t era = (y >= 0 ? y : y - 399) / 400;
  const unsigned yoe = (unsigned)(y - era * 400);
  const unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
  const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return era * 146097 + (int64_t)doe - 719468;
}

// +CCLK: "26/11/23,15:12:34-20"   (local time; last field = quarter-hours from UTC)
static bool parseCclk(const char* line, uint32_t* unixOut) {
  const char* q = strchr(line, '"');
  if (!q) return false;
  int yy, mo, dd, hh, mi, ss, tz = 0; char sign = '+';
  if (sscanf(q + 1, "%d/%d/%d,%d:%d:%d%c%d", &yy, &mo, &dd, &hh, &mi, &ss, &sign, &tz) < 6) return false;
  // An unsynced modem reports 1980 ("80/01/06"); two-digit years 24..79 mean 2024..2079.
  if (yy < 24 || yy > 79 || mo < 1 || mo > 12 || dd < 1 || dd > 31) return false;
  int64_t t = daysFromCivil(2000 + yy, mo, dd) * 86400 + hh * 3600 + mi * 60 + ss;
  int64_t offset = (int64_t)tz * 15 * 60;
  t += (sign == '-') ? offset : -offset;
  *unixOut = (uint32_t)t;
  return true;
}

struct GpsFix { bool valid; double lat, lon; float speedKmh; uint32_t utc; };

// +CGNSINF: 1,1,20261123151234.000,36.123456,-82.123456,500.1,12.30,90.0,1,...
static bool parseCgnsinf(const char* line, GpsFix* fix) {
  const char* p = strstr(line, "+CGNSINF:");
  if (!p) return false;
  p += 9;
  char fields[10][24] = {{0}};
  int f = 0, c = 0;
  for (; *p && f < 10; p++) {
    if (*p == ',') { fields[f][c] = 0; f++; c = 0; continue; }
    if (*p == ' ' || *p == '\r' || *p == '\n') continue;
    if (c < 23) fields[f][c++] = *p;
  }
  if (f < 7) return false;
  if (atoi(fields[1]) != 1) { fix->valid = false; return true; }   // running but no fix yet
  int Y, M, D, h, m, s;
  if (sscanf(fields[2], "%4d%2d%2d%2d%2d%2d", &Y, &M, &D, &h, &m, &s) != 6) return false;
  fix->utc = (uint32_t)(daysFromCivil(Y, M, D) * 86400 + h * 3600 + m * 60 + s);
  fix->lat = atof(fields[3]);
  fix->lon = atof(fields[4]);
  fix->speedKmh = (float)atof(fields[6]);
  fix->valid = !(fix->lat == 0 && fix->lon == 0);
  return true;
}

// Replay protection: remember the last few nonces we accepted.
static uint8_t seenNonces[16][8];
static uint8_t seenNext = 0;

static bool nonceSeen(const uint8_t* n) {
  for (int i = 0; i < 16; i++) if (memcmp(seenNonces[i], n, 8) == 0) return true;
  return false;
}

// Verifies a command packet from the relay. Returns a Result code
// (RES_NONE = valid; the caller then executes cmdOut).
static uint8_t lteVerifyCommand(const uint8_t* pkt, uint32_t nowUnix, uint8_t* cmdOut) {
  uint8_t expected[16];
  hmacTrunc("EMBR-LTE", pkt, 13, nullptr, 0, expected, 16);
  if (!constantTimeEqual(expected, pkt + 13, 16)) return RES_BAD_AUTH;
  uint32_t ts = ((uint32_t)pkt[1] << 24) | ((uint32_t)pkt[2] << 16) | ((uint32_t)pkt[3] << 8) | pkt[4];
  if (nowUnix == 0) return RES_BAD_AUTH;                                  // no trustworthy clock yet
  uint32_t skew = ts > nowUnix ? ts - nowUnix : nowUnix - ts;
  if (skew > LTE_MAX_SKEW) return RES_BAD_AUTH;                           // too old (or replayed later)
  if (nonceSeen(pkt + 5)) return RES_BAD_AUTH;                            // already used
  memcpy(seenNonces[seenNext], pkt + 5, 8);
  seenNext = (seenNext + 1) % 16;
  *cmdOut = pkt[0];
  return RES_NONE;
}

// Pulls up to `max` 58-hex-char packets out of {"commands":["..",".."],"fast":true}
static int parseRelayResponse(const char* body, uint8_t out[][LTE_PACKET_LEN], int max, bool* fast) {
  *fast = strstr(body, "\"fast\":true") != nullptr;
  const char* p = strstr(body, "\"commands\":[");
  if (!p) return 0;
  p += 12;
  int n = 0;
  while (*p && *p != ']' && n < max) {
    const char* q = strchr(p, '"');
    if (!q) break;
    const char* e = strchr(q + 1, '"');
    if (!e) break;
    if (e - (q + 1) == (int)(LTE_PACKET_LEN * 2) && fromHex(q + 1, out[n], LTE_PACKET_LEN)) n++;
    p = e + 1;
  }
  return n;
}

// ---- Shared state between loop() and the LTE task -------------------------

struct LteAck { uint8_t nonce[8]; uint8_t result; };
static LteAck lteAcks[8];
static volatile uint8_t lteAckCount = 0;
static uint8_t lteStatusSnapshot[STATUS_LEN];
static portMUX_TYPE lteMux = portMUX_INITIALIZER_UNLOCKED;

// Called from loop() after it executes a command that came over LTE.
static void lteRecordAck(const uint8_t* nonce, uint8_t result) {
  portENTER_CRITICAL(&lteMux);
  if (lteAckCount < 8) {
    memcpy(lteAcks[lteAckCount].nonce, nonce, 8);
    lteAcks[lteAckCount].result = result;
    lteAckCount++;
  }
  portEXIT_CRITICAL(&lteMux);
}

// Called from publishStatus() so the LTE task always has the latest status.
static void lteSnapshotStatus(const uint8_t* p) {
  portENTER_CRITICAL(&lteMux);
  memcpy(lteStatusSnapshot, p, STATUS_LEN);
  portEXIT_CRITICAL(&lteMux);
}

// Builds the JSON report. Returns its length.
static size_t buildReport(char* out, size_t cap, uint32_t nowUnix, const GpsFix& fix,
                          const uint8_t* status, int fuel, const LteAck* acks, int ackCount) {
  char st[STATUS_LEN * 2 + 1];
  toHex(status, STATUS_LEN, st);
  int n = snprintf(out, cap, "{\"v\":1,\"t\":%lu,\"st\":\"%s\",\"fuel\":%d", (unsigned long)nowUnix, st, fuel);
  if (fix.valid) {
    n += snprintf(out + n, cap - n, ",\"lat\":%.6f,\"lon\":%.6f,\"spd\":%.1f,\"fix\":%lu",
                  fix.lat, fix.lon, fix.speedKmh, (unsigned long)fix.utc);
  }
  n += snprintf(out + n, cap - n, ",\"ack\":[");
  for (int i = 0; i < ackCount; i++) {
    char id[17]; toHex(acks[i].nonce, 8, id);
    n += snprintf(out + n, cap - n, "%s{\"id\":\"%s\",\"r\":%u}", i ? "," : "", id, acks[i].result);
  }
  n += snprintf(out + n, cap - n, "]}");
  return (size_t)n;
}

// ---- Modem driver (only built with LTE_ENABLED) ---------------------------
#if LTE_ENABLED

#define MODEM Serial2

static char lteCarId[17], lteToken[33];
static uint32_t clockUnix = 0, clockAtMs = 0;       // last trusted time and when we got it
static GpsFix lastFix = {false, 0, 0, 0, 0};
static uint32_t lastFixMs = 0;
static uint32_t fastUntilMs = 0;
static bool httpOpen = false;

static uint32_t nowUnix() { return clockUnix ? clockUnix + (millis() - clockAtMs) / 1000 : 0; }

static void modemFlush() { while (MODEM.available()) MODEM.read(); }

// Reads one line (without CR/LF). Returns length, or -1 on timeout.
static int modemLine(char* buf, size_t cap, uint32_t timeoutMs) {
  size_t n = 0;
  uint32_t start = millis();
  while (millis() - start < timeoutMs) {
    while (MODEM.available()) {
      char c = (char)MODEM.read();
      if (c == '\r') continue;
      if (c == '\n') { if (n == 0) continue; buf[n] = 0; return (int)n; }
      if (n < cap - 1) buf[n++] = c;
    }
    delay(5);
  }
  buf[n] = 0;
  return n ? (int)n : -1;
}

// Sends a command and waits for OK/ERROR. If `prefix` is given, the first
// matching line is copied into `capture`.
static bool at(const char* cmd, uint32_t timeoutMs = 3000, const char* prefix = nullptr,
               char* capture = nullptr, size_t capLen = 0) {
  modemFlush();
  MODEM.print(cmd); MODEM.print("\r\n");
  char line[160];
  uint32_t start = millis();
  while (millis() - start < timeoutMs) {
    if (modemLine(line, sizeof(line), timeoutMs - (millis() - start)) < 0) break;
    if (prefix && capture && strncmp(line, prefix, strlen(prefix)) == 0) {
      strncpy(capture, line, capLen - 1); capture[capLen - 1] = 0;
    }
    if (strcmp(line, "OK") == 0) return true;
    if (strstr(line, "ERROR")) return false;
  }
  return false;
}

// Waits for a line starting with `prefix` (unsolicited result codes).
static bool waitFor(const char* prefix, char* capture, size_t capLen, uint32_t timeoutMs) {
  char line[160];
  uint32_t start = millis();
  while (millis() - start < timeoutMs) {
    if (modemLine(line, sizeof(line), timeoutMs - (millis() - start)) < 0) break;
    if (strncmp(line, prefix, strlen(prefix)) == 0) {
      if (capture) { strncpy(capture, line, capLen - 1); capture[capLen - 1] = 0; }
      return true;
    }
  }
  return false;
}

static bool modemBoot() {
  MODEM.begin(115200, SERIAL_8N1, PIN_MODEM_RX, PIN_MODEM_TX);
  for (int attempt = 0; attempt < 3; attempt++) {
    if (at("AT", 1000)) break;
    if (PIN_MODEM_PWRKEY >= 0) {                      // press the power key ~1.2 s
      pinMode(PIN_MODEM_PWRKEY, OUTPUT);
      digitalWrite(PIN_MODEM_PWRKEY, MODEM_PWRKEY_ACTIVE);
      delay(1200);
      digitalWrite(PIN_MODEM_PWRKEY, MODEM_PWRKEY_ACTIVE == HIGH ? LOW : HIGH);
    }
    delay(6000);
  }
  if (!at("AT", 1000)) { Serial.println("LTE: modem not answering"); return false; }
  at("ATE0");                                         // no command echo
  at("AT+CMEE=2");                                    // readable errors
  at("AT+CLTS=1");                                    // take the time from the network
  at("AT+CNMP=38");                                   // LTE only
  char rat[16]; snprintf(rat, sizeof(rat), "AT+CMNB=%d", LTE_RAT); at(rat);
  char apn[96]; snprintf(apn, sizeof(apn), "AT+CGDCONT=1,\"IP\",\"%s\"", LTE_APN); at(apn);
  at("AT+CFUN=1", 10000);
  Serial.println("LTE: modem ready");
  return true;
}

static bool registered() {
  char line[64] = {0};
  if (!at("AT+CEREG?", 2000, "+CEREG:", line, sizeof(line))) return false;
  const char* comma = strchr(line, ',');
  int stat = comma ? atoi(comma + 1) : 0;
  return stat == 1 || stat == 5;                      // home or roaming
}

static bool ensureNetwork() {
  for (int i = 0; i < 60 && !registered(); i++) delay(1000);   // up to a minute to find a tower
  if (!registered()) { Serial.println("LTE: no network"); return false; }
  char line[64] = {0};
  at("AT+CNACT?", 2000, "+CNACT: 0,", line, sizeof(line));
  if (strncmp(line, "+CNACT: 0,1", 11) != 0) {
    if (!at("AT+CNACT=0,1", 15000)) { Serial.println("LTE: data connection failed"); return false; }
  }
  return true;
}

static void syncClock() {
  char line[64] = {0};
  uint32_t t;
  if (at("AT+CCLK?", 2000, "+CCLK:", line, sizeof(line)) && parseCclk(line, &t)) {
    clockUnix = t; clockAtMs = millis();
  }
}

static void closeHttp() {
  if (httpOpen) { at("AT+SHDISC", 3000); httpOpen = false; }
}

static bool openHttp() {
  if (httpOpen) return true;
  char cmd[160];
  snprintf(cmd, sizeof(cmd), "AT+SHCONF=\"URL\",\"https://%s\"", RELAY_HOST); at(cmd);
  at("AT+SHCONF=\"BODYLEN\",1024");
  at("AT+SHCONF=\"HEADERLEN\",350");
  at("AT+CSSLCFG=\"sslversion\",1,3");                // TLS 1.2
  snprintf(cmd, sizeof(cmd), "AT+CSSLCFG=\"sni\",1,\"%s\"", RELAY_HOST); at(cmd);
  at("AT+SHSSL=1,\"\"");
  httpOpen = at("AT+SHCONN", 20000);
  if (!httpOpen) Serial.println("LTE: could not reach the relay");
  return httpOpen;
}

// POSTs `body` to `path`. Puts the response body in `resp`. Returns HTTP status (0 = failed).
static int httpPost(const char* path, const char* body, size_t len, const char* sigHex, char* resp, size_t respCap) {
  for (int attempt = 0; attempt < 2; attempt++) {
    if (!openHttp()) return 0;
    char cmd[200];
    at("AT+SHCHEAD");
    at("AT+SHAHEAD=\"Content-Type\",\"application/json\"");
    snprintf(cmd, sizeof(cmd), "AT+SHAHEAD=\"Authorization\",\"Bearer %s\"", lteToken); at(cmd);
    snprintf(cmd, sizeof(cmd), "AT+SHAHEAD=\"X-Ember-Sig\",\"%s\"", sigHex); at(cmd);

    // Body: wait for the '>' prompt, then send the bytes.
    modemFlush();
    snprintf(cmd, sizeof(cmd), "AT+SHBOD=%u,10000\r\n", (unsigned)len);
    MODEM.print(cmd);
    uint32_t start = millis(); bool prompt = false;
    while (millis() - start < 3000 && !prompt) { if (MODEM.available() && MODEM.read() == '>') prompt = true; else delay(5); }
    if (!prompt) { closeHttp(); continue; }
    MODEM.write((const uint8_t*)body, len);
    if (!waitFor("OK", nullptr, 0, 5000)) { closeHttp(); continue; }

    // Send it: "+SHREQ: "POST",200,123"
    snprintf(cmd, sizeof(cmd), "AT+SHREQ=\"%s\",3", path);
    if (!at(cmd, 5000)) { closeHttp(); continue; }
    char urc[96];
    if (!waitFor("+SHREQ:", urc, sizeof(urc), 30000)) { closeHttp(); continue; }
    int status = 0, rlen = 0;
    const char* c1 = strchr(urc, ',');
    if (c1) { status = atoi(c1 + 1); const char* c2 = strchr(c1 + 1, ','); if (c2) rlen = atoi(c2 + 1); }
    if (status == 0) { closeHttp(); continue; }

    // Read the response body.
    resp[0] = 0;
    if (rlen > 0) {
      if (rlen > (int)respCap - 1) rlen = (int)respCap - 1;
      modemFlush();
      snprintf(cmd, sizeof(cmd), "AT+SHREAD=0,%d\r\n", rlen);
      MODEM.print(cmd);
      if (waitFor("+SHREAD:", nullptr, 0, 5000)) {
        int got = 0; uint32_t t0 = millis();
        while (got < rlen && millis() - t0 < 5000) { if (MODEM.available()) resp[got++] = (char)MODEM.read(); else delay(2); }
        resp[got] = 0;
      }
      waitFor("OK", nullptr, 0, 2000);
    }
    return status;
  }
  return 0;
}

static void gpsFix(uint32_t timeoutMs) {
  closeHttp();                                        // GPS and LTE take turns on this modem
  at("AT+CGNSPWR=1");
  uint32_t start = millis();
  char line[160];
  while (millis() - start < timeoutMs) {
    delay(2000);
    line[0] = 0;
    GpsFix f;
    if (at("AT+CGNSINF", 2000, "+CGNSINF:", line, sizeof(line)) && parseCgnsinf(line, &f) && f.valid) {
      lastFix = f; lastFixMs = millis();
      if (!clockUnix) { clockUnix = f.utc; clockAtMs = millis(); }   // GPS time is a good clock too
      break;
    }
  }
  at("AT+CGNSPWR=0");
}

static void sendReport() {
  // Take the acks waiting to be reported.
  LteAck acks[8]; int ackCount;
  uint8_t status[STATUS_LEN];
  portENTER_CRITICAL(&lteMux);
  ackCount = lteAckCount;
  memcpy(acks, lteAcks, sizeof(LteAck) * ackCount);
  memcpy(status, lteStatusSnapshot, STATUS_LEN);
  portEXIT_CRITICAL(&lteMux);

  static char body[1024], resp[1200];
  size_t len = buildReport(body, sizeof(body), nowUnix(), lastFix, status, fuelPercent, acks, ackCount);
  uint8_t sig[16]; char sigHex[33];
  hmacTrunc("EMBR-RPT", (const uint8_t*)body, len, nullptr, 0, sig, 16);
  toHex(sig, 16, sigHex);

  char path[48]; snprintf(path, sizeof(path), "/v1/%s/report", lteCarId);
  int code = httpPost(path, body, len, sigHex, resp, sizeof(resp));
  if (code != 200) { Serial.printf("LTE: report failed (%d)\n", code); return; }

  // Delivered: drop the acks we just sent.
  portENTER_CRITICAL(&lteMux);
  int remaining = lteAckCount - ackCount;
  if (remaining > 0) memmove(lteAcks, lteAcks + ackCount, sizeof(LteAck) * remaining);
  lteAckCount = remaining > 0 ? remaining : 0;
  portEXIT_CRITICAL(&lteMux);

  // Commands from the app.
  uint8_t packets[8][LTE_PACKET_LEN];
  bool fast = false;
  int n = parseRelayResponse(resp, packets, 8, &fast);
  if (fast) fastUntilMs = millis() + 120000UL;
  for (int i = 0; i < n; i++) {
    QueuedCommand q = {0, RES_NONE, 1, {0}};
    memcpy(q.nonce, packets[i] + 5, 8);
    q.preResult = lteVerifyCommand(packets[i], nowUnix(), &q.cmd);
    if (q.preResult == RES_NONE) Serial.printf("LTE: command 0x%02X\n", q.cmd);
    xQueueSend(cmdQueue, &q, 0);
  }
}

static void lteTask(void*) {
  while (!modemBoot()) delay(60000);
  for (;;) {
    bool fast = (int32_t)(fastUntilMs - millis()) > 0;
    bool moving = lastFix.valid && lastFix.speedKmh > 5;
    bool needGps = !lastFixMs || fast || moving ||
                   millis() - lastFixMs > (uint32_t)GNSS_PARKED_MINUTES * 60000UL;
    if (needGps) gpsFix(lastFixMs ? 20000 : 90000);   // first fix can take a while
    if (ensureNetwork()) {
      syncClock();
      sendReport();
    }
    uint32_t wait = fast ? FAST_REPORT_SECONDS : (moving ? MOVING_REPORT_SECONDS : PARKED_REPORT_SECONDS);
    uint32_t start = millis();
    while (millis() - start < wait * 1000UL) {
      delay(250);
      if (lteAckCount > 0 && millis() - start > 1500) break;   // report command results right away
    }
  }
}

static void lteSetup() {
  deriveIds(lteCarId, lteToken);                      // before anything can send a report
  Serial.printf("LTE: car ID %s\n", lteCarId);
  xTaskCreatePinnedToCore(lteTask, "lte", 8192, nullptr, 1, nullptr, 0);
}

#else
static void lteSetup() {}
#endif
