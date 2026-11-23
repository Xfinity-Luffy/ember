// ===========================================================================
//  Ember Bridge — configuration
//  Edit this file before flashing. Everything car-specific lives here.
// ===========================================================================
#pragma once

// ---------------------------------------------------------------------------
//  Security  (CHANGE BOTH before flashing)
// ---------------------------------------------------------------------------

// 6-digit passkey iOS asks for the first time your phone pairs with the bridge.
// Pick your own. Must be 6 digits and must not start with 0.
// The firmware refuses to run while this is still the example 123456.
#define EMBER_PASSKEY        123456

// 32-byte shared secret, written as 64 hex characters.
// Generate one on any Mac/Linux terminal with:   openssl rand -hex 32
// Paste the SAME value into the app (Settings > Bridge key).
// The firmware refuses to run while this is still the placeholder.
#define EMBER_SECRET_HEX     "REPLACE_WITH_64_HEX_CHARACTERS_FROM_openssl_rand_-hex_32________"

// Name shown when the phone scans for the bridge.
#define EMBER_DEVICE_NAME    "Ember Bridge"

// ---------------------------------------------------------------------------
//  Outputs — each drives one relay (or optocoupler) channel that briefly
//  connects a remote-start-module trigger wire to ground.
//  Confirm which wire is which in your module's install guide.
//  Use -1 to disable an output.
//  Avoid ESP32 strapping pins (0, 2, 5, 12, 15) and GPIO 14 (glitches at boot).
// ---------------------------------------------------------------------------
#define PIN_LOCK             25
#define PIN_UNLOCK           26
#define PIN_START            27
#define PIN_STOP             -1   // -1 = module toggles start/stop on the START input
#define PIN_AUX1             32   // e.g. rear defrost trigger; -1 to disable

// Most cheap relay boards switch ON when the input pin is LOW.
// If your relays click at the wrong time, flip this to HIGH.
#define OUTPUT_ACTIVE_LEVEL  LOW

// How long each trigger is held, in milliseconds.
#define PULSE_MS             500

// ---------------------------------------------------------------------------
//  Hazards and alarm (Hazards and Alarm tabs). Each is a short pulse, like
//  pressing a button: one pulse turns it on, the next turns it off.
//  Use -1 to disable.
// ---------------------------------------------------------------------------
#define PIN_HAZARD           16   // relay across the hazard button, or a module output set to "hazards"
#define PIN_PANIC            17   // the remote-start module's panic input (horn + lights)
#define HAZARD_AUTO_OFF_MIN  10   // turn hazards off automatically after this many minutes
#define PANIC_SECONDS        30   // stop the panic alarm automatically after this long

// Optional input: the remote-start module's "alarm triggered" output (via an
// optocoupler, like the run-status input). Lets the app warn you the alarm went off.
#define PIN_ALARM_INPUT      18   // -1 if not wired
#define ALARM_ACTIVE_LEVEL   LOW

// ---------------------------------------------------------------------------
//  Optional input — "engine running" status from the module.
//  Strongly recommended: without it the bridge can only GUESS whether the
//  engine is running (it assumes the car runs for RUN_TIME_MINUTES after a
//  start it sent itself, and knows nothing about starts from the key fob).
//  Wire through an optocoupler; never connect 12 V straight to the ESP32.
// ---------------------------------------------------------------------------
#define PIN_RUN_STATUS       33   // -1 if not wired
#define RUN_STATUS_ACTIVE_LEVEL LOW  // LOW = optocoupler pulls the pin to ground when running

// Match the run time programmed into your remote-start module.
#define RUN_TIME_MINUTES     15

// ---------------------------------------------------------------------------
//  Abuse protection
// ---------------------------------------------------------------------------
#define MAX_BAD_AUTH         5      // bad keys in a row before lockout
#define LOCKOUT_SECONDS      60

// ---------------------------------------------------------------------------
//  Vehicle info (Vehicle tab in the app) — read from the car's OBD-II port.
//  Needs a 3.3 V CAN transceiver (e.g. SN65HVD230) wired to the OBD-II port:
//  CANH = pin 6, CANL = pin 14. Read-only: the bridge only sends standard
//  diagnostic requests and never changes anything in the car.
//  Set OBD_ENABLED to 0 if you haven't wired it.
// ---------------------------------------------------------------------------
#define OBD_ENABLED          1
#define PIN_CAN_TX           21   // to transceiver CTX / TXD
#define PIN_CAN_RX           22   // to transceiver CRX / RXD

// ---------------------------------------------------------------------------
//  Walk-away lock (turned on or off from the app's Settings).
//  When your phone's Bluetooth connection drops while the doors were left
//  unlocked and the engine is off, the bridge locks them after this many
//  seconds, unless the phone reconnects first.
// ---------------------------------------------------------------------------
#define WALK_AWAY_LOCK_SECONDS 30

// ---------------------------------------------------------------------------
//  Battery voltage (Home tab warning, low-battery check before remote start).
//  Read two ways:
//   * While the car is on: the standard OBD-II "control module voltage" (no extra wiring).
//   * Any time, even parked: a resistor divider from constant 12 V to an ADC pin.
//       car 12 V ──[100k]──┬──[22k]── GND
//                          └──▶ PIN_BATTERY_ADC
//     Use an input-only ADC1 pin (32–39). Set to -1 if you don't wire it.
// ---------------------------------------------------------------------------
#define PIN_BATTERY_ADC      35
#define BATTERY_DIVIDER_TOP_K    100   // resistor from 12 V, in kilohms
#define BATTERY_DIVIDER_BOTTOM_K 22    // resistor to ground, in kilohms
#define BATTERY_ADC_CAL_PERCENT  100   // fine-tune if your multimeter disagrees (e.g. 102)
#define FUEL_POLL_SECONDS    30   // how often to ask for fuel level while the car is on

// The bridge only asks the car for data while it's awake (engine running, or
// other traffic seen on the bus), so it never keeps a parked car's modules up.

// ---------------------------------------------------------------------------
//  Optional LTE + GPS (Cellular / Automatic connection in the app).
//  Adds a SIM7080G cellular + GPS module so the car can report its location
//  and take commands from anywhere, through your relay server (see README).
//  Leave LTE_ENABLED at 0 for Bluetooth only.
// ---------------------------------------------------------------------------
#define LTE_ENABLED          0

#define RELAY_HOST           "ember-relay.YOUR-SUBDOMAIN.workers.dev"  // your relay server's address (no https://)
#define LTE_APN              "hologram"   // your SIM provider's APN (from their setup page)
#define LTE_RAT              1            // 1 = LTE-M (Cat-M), 2 = NB-IoT, 3 = both

#define PIN_MODEM_TX         19   // ESP32 TX  -> modem RXD
#define PIN_MODEM_RX         34   // ESP32 RX  <- modem TXD (input-only pin is fine)
#define PIN_MODEM_PWRKEY     23   // pulses the modem's power key (-1 if your module powers on by itself)
#define MODEM_PWRKEY_ACTIVE  HIGH // most breakout boards: HIGH presses the key; bare modules: LOW

// How often the car checks in. Commands sent from the app over cellular are
// picked up at the next check-in, so shorter = snappier but more data/battery.
#define PARKED_REPORT_SECONDS  60   // parked
#define MOVING_REPORT_SECONDS  20   // driving
#define FAST_REPORT_SECONDS    8    // for 2 minutes after the app asks (map open, command sent)
#define GNSS_PARKED_MINUTES    10   // refresh GPS this often while parked
