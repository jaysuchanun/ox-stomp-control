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
  Verified 2026-10-21: the pedal is a MIDI *source* ("Oxstomp") but sends no MIDI when its footswitches
  or knobs are used — live state comes from the serial port instead (below).
  Jay's pedal Control (CC) channel is 1; Program Change is Omni.
  Footswitches are labelled **A** (left) and **B** (right); at power-up A is off, B is on (reverb).
  CC12/CC13 = 127 (then 0) toggles A/B exactly like stepping on them — the page's main footswitch buttons.
  CC19 does NOT behave as documented: 2 → B on works, but 0 from B-on changes nothing and 1 only blinks A
  orange. So `sendAll` no longer sends CC19, and `state.bypass` starts as null (unknown).
- **Live state over USB serial ("USB link" button, was "Read pedal"; Web Serial, added 2026-10-21).** The pedal's USB also exposes a CDC
  serial port (`/dev/cu.usbmodem…`, VID 0x2b5a) that UA Connect uses. Protocol ("UANet", from UA Connect's
  `@uaudio/*` JS modules): frames are `0x00 + COBS(block + crc7+1)` per 253-byte block + `0x00` (UA's CRC7 table is
  embedded in the page); handshake = send empty frame `00 02 01 00`, pedal echoes it; payload = protobuf
  `TransportFrame{1 clientId, 2 ClientPacket | 3 ServerPacket}`; ClientPacket `{1 path{1 daemonPath{1 port,2 path}|2 pathId},
  2 params{11 message_id,…}, 3 action(1 GET,2 SET,4 SUBSCRIBE), 4 data JSON, 5 gatewayCommand}`. Before use:
  gateway CHECK_CAPABILITIES (4) with `{"deflate":false}`, then REGISTER_PATH (1) `{path,port}` → `pathId`.
  Service ports: 4715 paneld (panel state), 4792 system (`/version/version/value` = 2.0.2). Replies > ~19 KB get
  truncated unless deflate is on — the page only reads small `/…/value` paths, so it keeps deflate off.
  SUBSCRIBE gives no pushes, so the page polls ~5×/s (each GET ≈ 2 ms). Useful paths (port 4715):
  `/panel/control/fs_led_left|right/state/value` (RGBA int: 255 = off, 0xFF0000FF = red),
  `/panel/control/knob_1..6/normalized_value/value` (4 = Mic 1, 5 = Rig, 6 = Mic 2; 1–3 top row),
  `/panel/emperor_state/{current_rig_index, current_cab_selection, current_mic1/2_selection,
  current_room_mic_selection, right_footswitch_mode}/value`. `bypassed_delay/_reverb` are stale (stay true with
  reverb on, don't change on FS press) — the page derives Delay/Reverb from the LEDs when right_footswitch_mode = 1
  ("Delay-Reverb": A = delay, B = reverb; Jay's setting; verified on the pedal 2026-10-21). Other modes show "—".
- **Rig settings live (sound engine "emperord", port 4740; 4718 is its other API).** Services found by scanning
  4700–4799: 4715 paneld, 4718/4740 emperord, 4792 smd, 4794 bled. `/mixers/<id>` has channels SLOT 1/2
  (Speaker Drive Pedal: `thermal`) and buses AUX 1/2 (H CM Plus: cab, mic, axis, hp = Mic 1/2), AUX 3/4 (Room Pedal
  L/R: room_mic, room_damp, room_hp, room_balance), MASTER (Cambridge EQ → UA 1176SE → Precision Delay Mod L →
  Plate 140 OX). Bus level/pan/mute: `<bus>/outputs/main/controls/{gain,pan,mute}`. Each control node has
  `normalized_value` (0–1) + `string_value` (UAFX Control's text, e.g. "420 ms"); 1176 on/off = effect node's
  `plugin_power`. `RIG_MAP` in index.html maps all 59 page controls; `discoverRig()` finds buses/effects by name and
  plugin id. While reading, controls show the pedal's value and text (`liveText`); a full sweep takes ~130 ms and
  the page reads 12 per poll cycle. OX "Output" is assumed to be MASTER gain (unverified). Delay/reverb `power`
  here is the real FX state (reverb On with B lit).
  Cab/mic/room indexes use the same tables as the CCs.
- **Two-way link: "USB link" / "Bluetooth" (added 2026-10-21, from reverse engineering UAFX Control 2.3.0 for Android).**
  The APK is a Capacitor app whose `bundle.js.map` carries UA's full TypeScript source; details in `docs/uafx-protocol.md`.
  Bluetooth is the same UANet protobuf as USB, minus COBS/CRC: GATT service `3bf93be5-20d2-47de-96d8-5d6fbb659220`,
  write `ef4ede65-…-ca5356090201`, notify `…090101`, MTU char `…0a0001` (u16 LE max, u16 LE usable block size);
  each write/notification is one block = 3-byte header (24-bit LE block number from 1, top bit = more) + payload.
  The first request (CHECK_CAPABILITIES) is re-sent every 200 ms (UA does 10×) since early BLE writes can be lost.
  **Writes** (what UAFX Control does): SET (action 2) on service *deviced*, port **4718**, path
  `/devices/81f8e32ffea347caba3c862ee77d2a7e/buses/<bus>/…/<control>/normalized_value/value/` (trailing `/`),
  data = JSON number 0–1. Buses: master `a9aed57a…`, mic1 `e352a52e…`, mic2 `a5163369…`, room L `56d54cfa…` + R `092624c0…`
  (room controls go to both). Master effects: effect_0 Cambridge EQ, effect_1 1176 (on/off = its `meter` control,
  OFF 0 … GR 3), effect_2 Precision Delay, effect_3 Plate. Cab/mic/room model: SET the paneld (4715)
  `/panel/emperor_state/current_*_selection/value` to the index — works for Cab even with no CC assigned.
  `WRITE_MAP` / `liveWrites()` in index.html hold the mapping. When linked, `sendParam` writes live instead of sending MIDI.
  Verified on Jay's pedal over USB 2026-10-21 (Master EQ High set, read back, restored; Cab set accepted).
  **Bluetooth not yet working on the pedal** (2026-10-21: Jay tried, USB fine). A new device only gets in after the pedal's
  **PAIR button** is pressed (UA's own scan/error text); recovery = forget pedal in OS Bluetooth, power-cycle, PAIR.
  BleLink now mirrors the app's connect steps (MTU max 0 = not ready, priming read of the notify char, 4 retries).
  Can't test headless here: macOS kills any process from Claude Code that touches Bluetooth (SIGABRT, no TCC permission).
  Verified in Chrome on the Mac 2026-10-21: the live panel follows the LEDs, Rig knob and knobs.
  On Jay's pedal `midi_cc_map` shows **Cab has no CC assigned (-1)**, so CC20 does nothing until set in UAFX Control.
- Send order (UA's rule): Program Change → Bypass (CC19) → everything else.
- MIDI CC/PC channels are **disabled by default** on the pedal; enable them in UAFX Control.
- Only one USB host at a time; UAFX Control over Bluetooth can stay connected.
- iOS browsers (Safari *and* Chrome on iOS) have no Web MIDI — the web page alone can't reach the pedal on iPhone.

## OX Stomp MIDI CC map (UA OX Stomp manual, fw 2.0)
7 Output · 12 FS Left (manual says 1 = press; pedal needs 127, page sends 127 then 0) · 13 FS Right (same) · 19 Bypass (0 bypass, 1 L FS, 2 R FS) · 20 Cab (0–21) ·
21 Speaker Drive · 22 Mic1 model (0–6) · 23 Mic1 Vol · 24 Mic1 Pan · 25 Mic1 Mute · 26 Mic1 Axis (0 off, 1 on) ·
27 Mic1 Low Cut · 28–33 same for Mic 2 · 34 Room Mic (0–5) · 35 Room level · 36 Room Pan · 37 Room Mute ·
38 Room Damp · 39 Room Low Cut · 40 Delay Enable · 41 Delay Time · 42 Delay Feedback · 44 Delay Mix ·
60 Reverb Enable · 61 Reverb Time/Decay · 63 Reverb Mix.
Mics: 0 Dyn 421, 1 Dyn 57, 2 Cond 414, 3 Ribbon 160, 4 Ribbon 121, 5 Cond 67, 6 Direct Box.
Rooms: 0 Cond Stereo, 1 Ribbon Stereo, 2 Cond Mono, 3 Cond 67 Mono, 4 Ribbon 84 Mono, 5 Ribbon 121 Mono.
Cabs 0–15 are from UA's table; 16–21 confirmed by UAFX Control 2.3.0's OX cab list (same order as the manual).
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
3. ~~Cab CC values 16–21~~ confirmed from the app 2026-10-21.
5. Bluetooth link with the real pedal (also: which link wins if UAFX Control on a phone is connected too).
4. The `≈` unit curves (delay time can be measured with an audio interface loopback).

## Possible next steps (Jay's call)
- Live at https://jaysuchanun.github.io/ox-stomp-control/ (repo github.com/jaysuchanun/ox-stomp-control; push to main redeploys).
- Ship the iOS app via TestFlight (needs the $99/yr Apple Developer Program).
- ESP32-S3 Wi-Fi bridge: serves the page over its own Wi-Fi and forwards WebSocket → USB-host MIDI, so any
  browser (incl. iPhone Safari) works and it doubles as a footswitch box.
- ~~Live control of the Rig-only parameters~~ done 2026-10-21 (USB link / Bluetooth) — was: would need reverse engineering UAFX Control's Bluetooth protocol
  (Android HCI snoop log + APK analysis with REA, which is installed on Jay's Mac). Interoperability with his
  own pedal only — no unlocking paid features or copying UA's DSP.
