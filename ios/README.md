# OX Stomp for iPhone

A native iOS wrapper around `ox-stomp-control.html`. The page runs unchanged inside a
WKWebView, and a small CoreMIDI bridge gives it Web MIDI, so it can talk to the OX Stomp
over the iPhone's USB-C port (Safari can't do this on its own).

```
OXStomp/
  OXStompApp.swift        app entry point
  StompWebView.swift      web view + Web MIDI shim + alert/prompt/share handling
  MIDIBridge.swift        CoreMIDI: list USB MIDI devices, send CC / Program Change
  ox-stomp-control.html   the controller page (same as the desktop version)
project.yml               XcodeGen spec
```

## What you need

- A Mac with **Xcode** (free, Mac App Store)
- An **Apple ID** signed in to Xcode (Xcode → Settings → Accounts)
- An iPhone with **USB-C** (iPhone 15 or newer). Lightning iPhones need Apple's
  Lightning-to-USB 3 Camera Adapter.
- A **USB-C to USB-C data cable**, plus the pedal's normal 9 V supply — the iPhone does not power the pedal.

## Build it (option A — XcodeGen, one command)

```sh
brew install xcodegen        # once
cd ios
xcodegen generate
open OXStomp.xcodeproj
```

## Build it (option B — no Homebrew)

1. Xcode → File → New → Project → **iOS → App**. Product Name `OXStomp`, Interface **SwiftUI**, Language **Swift**.
2. Delete the generated `ContentView.swift` and the generated `OXStompApp.swift`.
3. Drag the four files from the `OXStomp/` folder into the project navigator
   (tick **Copy items if needed** and the **OXStomp** target).

## Easiest long-term install (recommended)

Join the Apple Developer Program ($99/yr), then in Xcode use **Product → Archive → Distribute App → TestFlight**.
Install the free **TestFlight** app on the iPhone and install OX Stomp from there. It then behaves like any
App Store app: no cable to the Mac, no weekly re-signing, and updates arrive in TestFlight.

## Run it on your iPhone

1. Plug the iPhone into the Mac. On the iPhone: **Settings → Privacy & Security → Developer Mode → On** (restarts the phone).
2. In Xcode, select the **OXStomp** target → **Signing & Capabilities** → Team = your Apple ID.
   If the bundle ID is taken, change `com.jay.oxstomp` to something unique.
3. Choose your iPhone as the run destination and press **Run** (⌘R).
4. First launch only: **Settings → General → VPN & Device Management** → trust your developer certificate.

A free Apple ID signs the app for **7 days**; after that, plug in and press Run again.
A paid Apple Developer account ($99/yr) signs it for a year and allows TestFlight.

## Use it with the pedal

1. Pedal on firmware 2.0+, MIDI CC and PC channels enabled in UAFX Control (both are off by default).
2. Power the pedal, open the OX Stomp app, connect the pedal to the iPhone with the USB-C cable.
3. The app connects by itself — the status line changes to **Connected: …** as soon as the pedal is plugged in.
   Set the channel once to match UAFX Control; the app remembers it (and the pedal) next time.
4. Test with **Bypass** / **Left FS on** — the MIDI log shows each message sent.

Notes
- If no output appears, the pedal isn't presenting itself as a USB MIDI device to the phone —
  check firmware and that UAFX Control isn't connected to it over USB at the same time
  (UA allows only one USB host connection). UAFX Control over **Bluetooth** can stay connected.
- **Export** opens the iOS share sheet (save to Files, AirDrop to your Mac). **Import** uses the Files picker.
- Snapshots and the Rig Library are stored inside the app on the phone, separate from Chrome on the Mac.
