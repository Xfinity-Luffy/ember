# Ember — phone remote for a 2021 Mazda3

Ember lets your iPhone lock, unlock, start and stop your car over Bluetooth, and trigger rear defrost while the engine runs. It's your own app and design. It doesn't use Mazda's servers, subscription or branding.

```
 iPhone (Ember app)  ──Bluetooth──▶  ESP32 "Ember Bridge"  ──relays──▶  Fortin remote-start module  ──▶  car
```

| Folder | What it is |
|---|---|
| `ios/Ember/` | The iPhone app (SwiftUI, iOS 17+). Starts in **demo mode**, so you can try it right away. |
| `firmware/EmberBridge/` | Firmware for the ESP32 board in the car. Settings live in `config.h`. |

---

## 1. Put the app on your iPhone

Pick **1A** if you only have a Windows PC, or **1B** if you have a Mac.

### 1A. From a Windows PC (GitHub builds it, Sideloadly installs it)

**One-time setup**

1. Create a free account at **github.com**, then click **New repository**. Name it `ember`. Public or private both work: your secret key is never in the code. Public gives unlimited free build time. Private gives about 200 free Mac build minutes a month, which is roughly 20 builds.
2. Install **GitHub Desktop** (desktop.github.com) and sign in. Choose **File › Clone repository**, pick `ember`, and note the folder it creates.
3. Unzip `ember.zip` and copy everything *inside* the `ember` folder into that cloned folder, **including the hidden `.github` folder**. You should end up with `.github`, `firmware`, `ios` and `README.md` at the top level.
4. In GitHub Desktop, type a summary like "First upload", click **Commit to main**, then **Push origin**.

**Build the app**

5. On github.com, open your repo › **Actions** tab. If asked, click the button to enable workflows.
6. Click **Build iPhone app** › **Run workflow** › **Run workflow**. (Later pushes that change `ios/` start it automatically.)
7. Wait about 5–10 minutes for a green check. Open the run, scroll to **Artifacts**, and download **Ember-ipa**. Unzip it to get `Ember.ipa`.
   *Red ✗ instead?* Download the **build-log** artifact and send it to Claude to fix.

**Install it**

8. Install **iTunes from apple.com/itunes** (the Microsoft Store version does **not** work with Sideloadly), then **Sideloadly** from sideloadly.io.
9. Plug your iPhone into the PC with a cable. Tap **Trust** on the phone if asked.
10. In Sideloadly, pick your iPhone, type your Apple ID, drag `Ember.ipa` onto the window, and click **Start**. Enter your Apple ID password and the 2-factor code when asked. These go to Apple, not Sideloadly. Some people prefer a spare Apple ID for this.
11. On the iPhone:
    - **Settings › General › VPN & Device Management** › tap your Apple ID › **Trust**.
    - **Settings › Privacy & Security › Developer Mode** › turn on, then restart when asked.
12. Open **Ember**. It starts in demo mode.

**The 7-day limit:** with a free Apple ID the app stops opening after 7 days. In Sideloadly's options, turn on **automatic refresh** when you install. Your PC then re-signs the app in the background whenever the iPhone is connected by cable or on the same Wi-Fi. If it lapses, just repeat step 10; your settings and key are kept.

### 1B. From a Mac with Xcode

You need a **Mac with Xcode 16 or newer** (free from the Mac App Store) and your iPhone.
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

**Battery draw:** the bridge stays awake to listen for your phone, drawing roughly 30–60 mA. That's fine for a daily driver. If the car will sit for several weeks, unplug the bridge's fuse.

---

## 4. Flash the bridge

1. Install the **Arduino IDE**.
2. **Settings › Additional boards manager URLs:** add `https://espressif.github.io/arduino-esp32/package_esp32_index.json`, then install **esp32 by Espressif** from Boards Manager.
3. **Library Manager:** install **NimBLE-Arduino** by h2zero, **version 2.x**.
4. Open `firmware/EmberBridge/EmberBridge.ino` and edit `config.h`:
   - `EMBER_PASSKEY`: choose your own 6-digit number.
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

Commands: `01` lock, `02` unlock, `03` start, `04` stop, `05` aux1 (defrost).
Flags: bit0 running, bit1 status wired, bit2 lock known, bit3 locked.
Results: 0 none, 1 ok, 2 bad key, 3 already running, 4 not running, 5 locked out, 6 bad format, 7 output not wired.
