# Ember — phone remote for a 2021 Mazda3

Ember lets your iPhone lock, unlock, start and stop your car over Bluetooth, and turn on rear defrost. It's your own app and design. It doesn't use Mazda's servers, subscription or branding.

```
 iPhone (Ember app)  ──Bluetooth──▶  ESP32 "Ember Bridge"  ──relays──▶  Fortin remote-start module  ──▶  car
```

| Folder | What it is |
|---|---|
| `ios/Ember/` | The iPhone app (SwiftUI, iOS 17+). Starts in **demo mode**, so you can try it right away. |
| `ios/tools/` | Draws the app icon during the build. |
| `firmware/EmberBridge/` | Firmware for the ESP32 board in the car. Settings live in `config.h`. |
| `.github/workflows/` | The cloud build that turns the code into an installable `Ember.ipa`. |

### What's in the app

- **Main screen:** a status card in plain English, a press-and-hold power button (a quick tap explains the gesture), an "Also turn on rear defrost" switch, and Lock / Unlock with the current state checked.
- **Look:** Liquid Glass on iOS 26 (frosted glass on iOS 17–18) over a slowly drifting night-sky background that glows warmer while the engine runs.
- **Vehicle tab:** a fuel gauge read from the car's diagnostic port (OBD-II), and a tire-pressure diagram that flags low tires (tire readings need extra work, see Wiring).
- **Hazards tab:** a big blinking triangle to turn the hazard lights on or off, with an automatic 10-minute shut-off.
- **Alarm tab:** armed or not (from the lock state), a warning when the alarm went off, and a press-and-hold panic button.
- **Settings:** car name, demo mode, connection status, bridge key, Face ID for Unlock and Start, defrost with every start, vibration feedback, "Find my bridge again", and pairing help.

---

## 1. Put the app on your iPhone

Pick **1A** if you only have a Windows PC, or **1B** if you have a Mac.

### 1A. From a Windows PC (GitHub builds it, Sideloadly installs it)

The repository **github.com/Xfinity-Luffy/ember** builds the app by itself every time code under `ios/` changes. You can also start a build any time from **Actions › Build iPhone app › Run workflow**.

**Get the app file**

1. Open the repository's **Actions** tab and click the newest **Build iPhone app** run with a green check.
2. Scroll to **Artifacts** and download **Ember-ipa**. Unzip it to get `Ember.ipa`.
   *Red ✗ instead?* Download the **build-log** artifact and send it to Claude to fix.

**Install it**

3. Install **iTunes from apple.com/itunes** (the Microsoft Store version does **not** work with Sideloadly), then **Sideloadly** from sideloadly.io.
4. Plug your iPhone into the PC with a cable. Tap **Trust** on the phone if asked.
5. In Sideloadly, pick your iPhone, type your Apple ID, drag `Ember.ipa` onto the window, and click **Start**. Enter your Apple ID password and the 2-factor code when asked. These go to Apple, not Sideloadly. Some people prefer a spare Apple ID for this.
6. On the iPhone:
   - **Settings › General › VPN & Device Management** › tap your Apple ID › **Trust**.
   - **Settings › Privacy & Security › Developer Mode** › turn on, then restart when asked.
7. Open **Ember**. It starts in demo mode.

**The 7-day limit:** with a free Apple ID the app stops opening after 7 days. In Sideloadly's options, turn on **automatic refresh** when you install. Your PC then re-signs the app in the background whenever the iPhone is connected by cable or on the same Wi-Fi. If it lapses, just repeat step 5; your settings and key are kept.

**Changing files on GitHub in the browser:** use **Add file › Upload files** and drag in only the files you changed. Each one must land in its folder (for example `ios/Ember/ContentView.swift`). Open that folder on GitHub first, then upload, so the files go to the right place.

### 1B. From a Mac with Xcode

You need a **Mac with Xcode 26 or newer** (free from the Mac App Store; older Xcode can't build the Liquid Glass code) and your iPhone.
*(Shortcut: `brew install xcodegen`, then run `xcodegen generate` in the `ios` folder and open `Ember.xcodeproj`. Steps 1–4 below are then already done except picking your Team. Run `python3 tools/make_icon.py Ember/Assets.xcassets/AppIcon.appiconset/icon.png` first to draw the app icon.)*

1. Xcode › **File › New › Project › iOS › App**. Name it `Ember`, Interface **SwiftUI**, Language **Swift**.
2. In the new project, delete the generated `ContentView.swift` and `EmberApp.swift`.
3. Drag every `.swift` file and the `Assets.xcassets` folder from `ios/Ember/` into the project (tick **Copy items if needed**; replace the generated Assets when asked).
4. Select the **Ember** target:
   - **General › Minimum Deployments:** iOS 17.0
   - **Info** tab: add the key **Privacy – Bluetooth Always Usage Description** with a value like `Ember connects to your car's bridge over Bluetooth.` *(Without this the app crashes when it first uses Bluetooth.)*
   - **Signing & Capabilities:** pick your Apple ID as the Team.
5. Plug in your iPhone, select it as the run destination, and press ▶. The first time, approve the developer on the phone under **Settings › General › VPN & Device Management**, and turn on **Developer Mode** if iOS asks.

Hold the big power button for one second to "start" the demo car.

> **Free Apple ID vs paid:** With a free Apple ID the app works for 7 days, then you re-run it from Xcode. A paid Apple Developer account ($99/yr) extends that to a year.

---

## 2. Parts list

| Part | Notes | Approx. |
|---|---|---|
| Fortin **EVO-ONE** + **THAR-ONE-MAZ5** T-harness (or the EVO-MAZT4 kit) | Remote starter + immobilizer bypass for 2019–2022 Mazda3 push-to-start. Confirm with Fortin's vehicle lookup for your exact trim. Needs a Flash-Link updater for setup (installers have one). | $150–300 |
| Professional install of the Fortin module | Recommended: it ties into the car's security system. | varies |
| ESP32 dev board (ESP32-WROOM-32 / DevKitC) | Must be the original ESP32 or ESP32-S3/C3 (all have BLE). | $8–15 |
| 4-channel relay board, 3.3 V-logic compatible (or optocoupler board) | One channel each for lock, unlock, start, defrost. | $8 |
| PC817 optocoupler module | For the optional "engine running" input. Strongly recommended. | $5 |
| 12 V → 5 V buck converter (≥1 A) + inline fuse holder with 2 A fuse | Powers the ESP32 from the car. | $10 |
| Wire, crimp connectors, small project box | | $10 |

---

## 3. Wiring

**Have the installer (or the Fortin install guide for your exact harness) confirm which wire is which before connecting anything.** Fortin modules accept ground-trigger inputs for lock/unlock/start and can output an "engine running" status. Which wire does what depends on the module's programming.

```
 Car constant 12V ──[2A fuse]──▶ Buck converter IN+        Buck OUT 5V ──▶ ESP32 5V/VIN
 Car ground ───────────────────▶ Buck converter IN−        Buck OUT GND ─▶ ESP32 GND

 ESP32 GPIO25 ──▶ Relay 1 IN      Relay 1: COM ─ ground,  NO ─ module LOCK trigger input
 ESP32 GPIO26 ──▶ Relay 2 IN      Relay 2: COM ─ ground,  NO ─ module UNLOCK trigger input
 ESP32 GPIO27 ──▶ Relay 3 IN      Relay 3: COM ─ ground,  NO ─ module REMOTE-START trigger input
 ESP32 GPIO32 ──▶ Relay 4 IN      Relay 4: COM ─ ground,  NO ─ module AUX / rear-defrost input (optional)
 Relay board VCC/GND ◀── ESP32 5V / GND

 Module "ground-when-running" output ──▶ optocoupler input (with its resistor)
 Optocoupler output ──▶ ESP32 GPIO33 and GND
```

Pin numbers are set in `config.h`, so you can change them. Never connect 12 V directly to an ESP32 pin.

**Optional: hazards and alarm (Hazards and Alarm tabs).** Two more relay channels and one more optocoupler input:

```
 ESP32 GPIO16 ──▶ Relay 5 IN   Relay 5: across the hazard button's contacts, or a module output set to hazards
 ESP32 GPIO17 ──▶ Relay 6 IN   Relay 6: COM ─ ground, NO ─ module PANIC trigger input (horn + lights)
 Module "alarm triggered" output ──▶ optocoupler ──▶ ESP32 GPIO18 and GND   (lets the app warn you)
```

Each output is a short pulse, like pressing a button once. The bridge turns hazards off after 10 minutes and stops the panic alarm after 30 seconds (`HAZARD_AUTO_OFF_MIN` and `PANIC_SECONDS` in `config.h`). Have the installer confirm which module wires do this on your setup, and set any pin you don't wire to `-1`. The alarm warning only reaches your phone while it's connected to the bridge over Bluetooth.

**Optional: fuel level for the Vehicle tab.** Add a 3.3 V CAN transceiver board (SN65HVD230, about $5) and an OBD-II splitter or pigtail cable, so you never cut the car's wiring:

```
 ESP32 3.3V ──▶ transceiver 3V3        ESP32 GND ──▶ transceiver GND
 ESP32 GPIO21 ──▶ transceiver CTX      ESP32 GPIO22 ──▶ transceiver CRX
 transceiver CANH ──▶ OBD-II pin 6     transceiver CANL ──▶ OBD-II pin 14
```

The bridge only *reads*: it sends the standard "fuel tank level" request and never changes anything in the car. It also only asks while the car is awake (engine running, or the car's own modules already talking), so it can't keep a parked car awake and drain the battery. The reading shows as "Updated N min ago" afterward. If you don't wire this, set `OBD_ENABLED` to `0` in `config.h`.

**Tire pressure:** your 2021 Mazda3 has a sensor in each tire, but the car shares those readings only in a Mazda-specific format that isn't publicly documented. The Vehicle tab shows tire pressures in demo mode and is ready for real readings, but shows "Not set up yet" until the bridge learns that format.

**Battery draw:** the bridge stays awake to listen for your phone, drawing roughly 30–60 mA. That's fine for a daily driver. If the car will sit for several weeks, unplug the bridge's fuse.

---

## 4. Flash the bridge

1. Install the **Arduino IDE**.
2. **Settings › Additional boards manager URLs:** add `https://espressif.github.io/arduino-esp32/package_esp32_index.json`, then install **esp32 by Espressif** from Boards Manager.
3. **Library Manager:** install **NimBLE-Arduino** by h2zero, **version 2.x**.
4. Open `firmware/EmberBridge/EmberBridge.ino` and edit `config.h`:
   - `EMBER_PASSKEY`: choose your own 6-digit number. The bridge refuses to run with the example `123456`.
   - `EMBER_SECRET_HEX`: run `openssl rand -hex 32` in Terminal and paste the 64-character result. **Keep this private.**
   - `RUN_TIME_MINUTES`: match the run time programmed in the Fortin module.
   - If the status input isn't wired, set `PIN_RUN_STATUS` to `-1`.
5. Board: **ESP32 Dev Module**. Select the USB port and click Upload.
6. Open **Serial Monitor** at 115200 baud. You should see `Advertising. Waiting for the app.`

**Test on the bench before installing.** Watch the relays click for each command before wiring to the car.

---

## 5. Connect the app to the car

1. In the app: **Settings › Bridge key** → paste the same 64-character secret → **Save key**.
   *(To get it onto your phone, copy it on the Mac and use Universal Clipboard, or AirDrop a note to yourself.)*
2. Turn **Demo mode** off.
3. Within ~10 m of the bridge, the status changes from "Looking for car" to a pairing prompt. Enter your `EMBER_PASSKEY`.
4. Status shows **Connected**. Try Lock, then Unlock, then hold the power button to start.

After that, the app reconnects automatically whenever you open it near the car.

---

## How security works

- **Encrypted, paired link.** The bridge only talks over an encrypted Bluetooth connection paired with your passkey.
- **Signed, one-time commands.** Before each command the app reads a random 16-byte challenge from the bridge. It sends the command plus an HMAC-SHA256 signature over that challenge, made with the secret key. The bridge checks the signature and then throws the challenge away. Someone who records your Bluetooth traffic can't replay it, and someone who only knows the passkey can't send commands.
- **Lockout.** 5 bad signatures in a row lock the bridge for 60 seconds.
- **The key stays on your phone.** It's stored in the iPhone Keychain, set to "this device only".
- **The car's own protections still apply.** The Fortin module handles the immobilizer bypass and shuts the engine off if someone tries to drive without the key.

## Good to know

- **Climate:** a 2021 Mazda3's heat and A/C run at the settings you left when you parked. Set them before you leave the car. The Defrost button pulses the AUX output, if you've wired and programmed it in the Fortin module.
- **Lock highlight** shows the last command sent from the app, not a live door sensor.
- **Without the status input,** the bridge can't see starts made with the key fob. It assumes a start it sent itself keeps running for `RUN_TIME_MINUTES`. Wire the status input for accurate info.
- **Range** is Bluetooth range, roughly 10–30 m depending on walls. Adding cellular later would mean adding an LTE board and a small server. The app's transport layer (`CarTransport`) is built so that can be swapped in.
- Check local rules on unattended idling before using remote start.

## Protocol reference (for future changes)

| Characteristic | UUID | Access | Content |
|---|---|---|---|
| Service | `e1ff55ff-6a97-433b-bea8-9ec4b34f384e` | | |
| Challenge | `19761279-973c-47a5-8d3d-08d03f22677c` | read, encrypted | 16 random bytes, new after every command |
| Command | `6a4d6a66-0fe9-48ca-878e-238060417a9d` | write, encrypted | `[cmd][HMAC-SHA256(key, "EMBR" ‖ challenge ‖ cmd)[0..16]]` |
| Status | `7bdb2e96-9fcf-4522-b098-7264afa1c44d` | read/notify, encrypted | `[1][flags][secs LE16][lastResult][seq]` |

Commands: `01` lock, `02` unlock, `03` start, `04` stop, `05` aux1 (defrost), `06`/`07` hazards on/off, `08`/`09` panic on/off, `0A` clear alarm warning.
Flags: bit0 running, bit1 status wired, bit2 lock known, bit3 locked, bit4 hazards on, bit5 panic on, bit6 alarm went off, bit7 alarm input wired. Newer bridges add hazard and panic seconds left (LE16 each) after `seq`.
Results: 0 none, 1 ok, 2 bad key, 3 already running, 4 not running, 5 locked out, 6 bad format, 7 output not wired.
