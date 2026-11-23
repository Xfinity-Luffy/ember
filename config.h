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
