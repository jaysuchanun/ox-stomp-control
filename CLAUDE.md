# OX Stomp Controller — project brief

Jay's controller for the **Universal Audio UAFX OX Stomp** (Dynamic Speaker Emulator) pedal,
modeled on UA's UAFX Control app. Jay is an electrical engineer (embedded / ESP32 background).

## Layout
- `web/index.html` — the whole controller: one self-contained HTML/CSS/JS page using Web MIDI.
- `web/` is also an installable PWA: `manifest.webmanifest`, `sw.js` (offline cache), `icons/`
  (`icon.svg` is the source; PNGs rendered with `qlmanage -t -s 512` + `sips -z`), `.nojekyll`.
  All paths are relative so it works under `https://<user>.github.io/<repo>/`.
  **Bump `VERSION` in `sw.js` whenever a file in its `ASSETS` list changes.** The page registers the
  service worker only over http(s), so the iOS wrapper (file://) is unaffected.
- `.github/workflows/pages.yml` deploys `web/` to GitHub Pages on push to `main` (assumes this folder is
  the repo root; Settings → Pages → Source = GitHub Actions). Local test: `python3 -m http.server -d web`.
- `ios/` — native iPhone wrapper (SwiftUI + WKWebView + CoreMIDI). `ios/OXStomp/ox-stomp-control.html`
  is a copy of `web/index.html`; **keep the two identical** (copy web → ios after every change).
  Build with `cd ios && xcodegen generate` (see `ios/README.md`).

## How it talks to the pedal
- **USB MIDI** (pedal firmware 2.0+). Mac/Windows/Android: Chrome Web MIDI. iPhone: CoreMIDI via the
  wrapper, which injects a `navigator.requestMIDIAccess` shim (`StompWebView.swift`) — the page code
  doesn't know the difference. Inside the wrapper the page auto-connects and hides the Connect button.
- Messages: CC `[0xB0|ch, cc, value]`, Program Change `[0xC0|ch, n]`. One-way: the pedal never reports state.
- Send order (UA's rule): Program Change → Bypass (CC19) → everything else.
- MIDI CC/PC channels are **disabled by default** on the pedal; enable them in UAFX Control.
- Only one USB host at a time; UAFX Control over Bluetooth can stay connected.
- iOS browsers (Safari *and* Chrome on iOS) have no Web MIDI — the web page alone can't reach the pedal on iPhone.

## OX Stomp MIDI CC map (UA OX Stomp manual, fw 2.0)
7 Output · 12 FS Left (1 = press) · 13 FS Right · 19 Bypass (0 bypass, 1 L FS, 2 R FS) · 20 Cab (0–21) ·
21 Speaker Drive · 22 Mic1 model (0–6) · 23 Mic1 Vol · 24 Mic1 Pan · 25 Mic1 Mute · 26 Mic1 Axis (0 off, 1 on) ·
27 Mic1 Low Cut · 28–33 same for Mic 2 · 34 Room Mic (0–5) · 35 Room level · 36 Room Pan · 37 Room Mute ·
38 Room Damp · 39 Room Low Cut · 40 Delay Enable · 41 Delay Time · 42 Delay Feedback · 44 Delay Mix ·
60 Reverb Enable · 61 Reverb Time/Decay · 63 Reverb Mix.
Mics: 0 Dyn 421, 1 Dyn 57, 2 Cond 414, 3 Ribbon 160, 4 Ribbon 121, 5 Cond 67, 6 Direct Box.
Rooms: 0 Cond Stereo, 1 Ribbon Stereo, 2 Cond Mono, 3 Cond 67 Mono, 4 Ribbon 84 Mono, 5 Ribbon 121 Mono.
Cabs 0–15 are from UA's table; **16–21 are inferred** from the manual's cabinet list order — unverified.
Source: https://help.uaudio.com/hc/en-us/articles/13621362465300

## UI conventions in index.html
- Each control is declared in `SECTIONS` (`id, cc, label, type: range|select|toggle, def, unit`).
- **CC-tagged** (gold) controls send MIDI live. **Rig-tagged** (`nomidi:true`, blue) controls have no CC on
  the pedal (Master EQ, the whole 1176, delay mode/time B/pans/LFO/mod/cuts, reverb balance/treble/bass);
  they are kept in snapshots/Rigs as a record and must be set in UAFX Control, then recalled via Program Change.
- Values marked `≈` are estimates: UA publishes range end points (from the app's slider labels) but not the
  curves. Delay time 0.14 ms–3 s assumed log; reverb mix 15% wet at midpoint (UA); 1176 attack/release log.
- Links: Delay Time B follows A and Pan B mirrors A while Link is on (`linkedTo` / `mirrorOf` / `linkKey`).
- Rig Library saves the whole page `state` + PC number; Recall loads the page and sends the PC.
- Storage: `localStorage` keys `oxStompSnapshots`, `oxStompRigLib`, `oxStompChannel`, `oxStompOutputName`
  (always wrapped in try/catch).

## Not yet verified on real hardware
1. ~~Mac~~ verified 2026-10-21: enumerates as "Oxstomp" (USB VID 0x2b5a PID 0x0038) and CC19 on ch 1 toggles bypass
   (pedal Control channel must be set; it was Disable). iPhone still unverified.
   Chrome needs the site's "MIDI devices" permission; if its prompt is missed, requestMIDIAccess just hangs.
   Live page in Chrome on the Mac verified the same day: connects and controls the pedal.
2. Does CC41 move Time A only, or A and B together when linked?
3. Cab CC values 16–21.
4. The `≈` unit curves (delay time can be measured with an audio interface loopback).

## Possible next steps (Jay's call)
- Live at https://jaysuchanun.github.io/ox-stomp-control/ (repo github.com/jaysuchanun/ox-stomp-control; push to main redeploys).
- Ship the iOS app via TestFlight (needs the $99/yr Apple Developer Program).
- ESP32-S3 Wi-Fi bridge: serves the page over its own Wi-Fi and forwards WebSocket → USB-host MIDI, so any
  browser (incl. iPhone Safari) works and it doubles as a footswitch box.
- Live control of the Rig-only parameters would need reverse engineering UAFX Control's Bluetooth protocol
  (Android HCI snoop log + APK analysis with REA, which is installed on Jay's Mac). Interoperability with his
  own pedal only — no unlocking paid features or copying UA's DSP.
