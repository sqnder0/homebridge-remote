# Homebridge Remote

An iPhone app to control Homebridge devices (starting with an air conditioner) from a
glassy UI and with Siri. No Apple TV / HomePod / Home hub needed: the app talks
straight to the Homebridge UI's REST API.

- Add any Homebridge device from inside the app, whenever you like
- Air-conditioner card: power, current temperature, target temperature, mode
- Siri via App Intents: "Turn on *Airco* in Homebridge Remote", "Turn off …",
  "Set the temperature of …". Devices you add show up in Siri automatically.

## Requirements on the Homebridge side

Homebridge UI (`homebridge-config-ui-x`) must allow accessory control. That is the
default on `hb-service` installs; if you run Homebridge in Docker, make sure
insecure mode is on (`-I`, or "Homebridge Insecure Mode" in the UI settings).

## Building without a Mac

1. Push to GitHub. The `Build IPA` workflow (`.github/workflows/build.yml`) builds an
   unsigned `HomebridgeRemote.ipa` on a macOS runner (XcodeGen + xcodebuild).
2. Download the `HomebridgeRemote-ipa` artifact from the Actions run.
3. Sign it with a free Apple ID and install it on your own iPhone, using a sideloading
   tool that works on your computer (AltServer-Linux / SideStore, or `zsign` +
   `ideviceinstaller`). Free signing lasts 7 days; re-sign to renew.
4. On the iPhone: Settings → Privacy & Security → Developer Mode → on.

## Project layout

| File | Purpose |
| --- | --- |
| `project.yml` | XcodeGen project definition |
| `HomebridgeClient.swift` | Homebridge REST client + accessory model |
| `Hub.swift` | App state, add/remove/rename, optimistic control |
| `Cards.swift`, `Components.swift`, `Screens.swift` | UI |
| `Intents.swift` | Siri / Shortcuts (App Intents) |
| `Storage.swift` | Settings, keychain, saved device list |
