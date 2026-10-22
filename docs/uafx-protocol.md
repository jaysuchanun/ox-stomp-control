# How UAFX Control talks to the OX Stomp

Notes from reverse engineering **UAFX Control 2.3.0 for Android** (`UAFX-Control_2.3.0.apks`), done 2026-10-21
for interoperability with Jay's own pedal. Nothing here unlocks paid features or copies UA's DSP.

## What the app is

- A **Capacitor** hybrid app: a thin Android shell (`classes.dex`) plus a web UI in `assets/public/bundle.js`
  (Aurelia + TypeScript). The bundle ships with its **source map**, so UA's original module tree is readable:
  `src/components/editors/ox-editor.ts` (the OX screen), `packages/lib-emperor/emperor-ble` (Bluetooth connection
  manager), `emperor-capacitor/ble.ts` (GATT calls), `lib/transport-ble` (block framing),
  `lib/message-format-protobuf` (the UANet protobuf schema), `uanet-connection-protobuf` (router / path registry).
- The pedal side is a small Linux system running UA's daemons — the same "UANet" services UA Connect uses on the desktop.
  The app talks to them over Bluetooth LE; UA Connect talks to them over the USB CDC serial port.

| Service  | Port | Used for |
|----------|------|----------|
| paneld   | 4715 | panel state: LEDs, knobs, `/panel/emperor_state/*` (rig index, cab / mic / room selection, footswitch mode) |
| deviced  | 4718 | the sound engine as a device tree — **all parameter writes**, preset export/import |
| mixerd   | 4740 | the mixer graph (`/mixers/…`) — the page reads Rig values here by plugin name |
| smd      | 4792 | system: `/version`, device info, registration, factory reset |

## Transport

**Bluetooth LE** (what the phone app uses)

- Advertised name starts with `UAFX`, manufacturer data company ID `0x09C2` (carries the serial number).
- GATT service `3bf93be5-20d2-47de-96d8-5d6fbb659220`
  - `ef4ede65-1906-4c39-8b88-ca5356090201` — write (app → pedal), write-with-response
  - `ef4ede65-1906-4c39-8b88-ca5356090101` — notify (pedal → app)
  - `ef4ede65-1906-4c39-8b88-ca53560a0001` — read: `u16 LE max MTU, u16 LE usable block size` (app wants usable ≥ 181)
- Every write / notification is one **block**: 3-byte header + payload.
  Header = block number (1, 2, 3 …) as 24-bit little-endian; the top bit of byte 3 means "more blocks follow".
  A message is the concatenation of its blocks' payloads. No COBS, no CRC.
- Connect sequence in the app: connect → read MTU → read the notify characteristic once → start notifications →
  send CHECK_CAPABILITIES ten times, 200 ms apart, until one is answered (early writes can be dropped).

**USB serial** (UA Connect, and this page's "USB link") — same messages, each framed as
`0x00 + COBS(block + CRC7+1)` per 253-byte block + `0x00`; handshake = empty frame `00 02 01 00`, echoed by the pedal.

## Messages (UANet protobuf)

`TransportFrame { 1 clientIdentifier, 2 ClientPacket | 3 ServerPacket }`

`ClientPacket { 1 path, 2 parameters, 3 action, 4 data, 5 gatewayCommand }`

- `path` = `{1 daemonPath{1 port, 2 path} | 2 pathId}` — strings are `messageString {1 literal | 2 deflate{1 size, 2 zlib}}`
- `action`: 1 GET, 2 SET, 3 POST, 4 SUBSCRIBE, 5 UNSUBSCRIBE
- `parameters`: 1 no_properties, 2 no_children, 3 no_commands, 4 no_propinfo, 5 no_propvalue, 6 flatvalue, 7 propfilter,
  8 recursive, 9 no_cmdparams, 10 cmd_id, 11 message_id (replies echo it), 12 levels, 13 extra_params
- `data` = JSON text
- Gateway commands (POST to `/`): 1 REGISTER_PATH `{path, port}` → `{pathId}`, 4 CHECK_CAPABILITIES `{deflate}`,
  plus LOOKUP_PATH, DISCONNECT, UNKNOWN_PATH_ID (re-register and resend).

Session: CHECK_CAPABILITIES → REGISTER_PATH for each `(port, path)` → GET / SET using the `pathId`.

## How the OX editor sets a control

`deviced.set({path, value})` → SET with the path plus a trailing `/` and the value as JSON:

```
/devices/81f8e32ffea347caba3c862ee77d2a7e/buses/<bus>/<node>/<control>/normalized_value/value/   ← 0…1
```

(The app uses `real_value/value` for switches and stepped controls; `normalized_value` 0/1 or index/(steps−1) is
equivalent and is what the page sends.)

| Bus | UID | Contents |
|-----|-----|----------|
| Master | `a9aed57a911d41208d3b24b1ff5cfd78` | `outputs/main/controls/gain` · effect_0 Cambridge EQ (`master_enable, hf/mf/lmf/lf_gain` + `_enable`, `hc_/lc_freq` + `_enable`) · effect_1 1176 (`input, output, attack, release, ratio`, on/off = `meter` OFF 0 / GR 3) · effect_2 Precision Delay (`power, mode, delay_a/b, link, recirc, mix, rate, depth, lfo, pan_a/b, pan_link, hi_pass, lo_pass, mute_a/b`) · effect_3 Plate (`power, reverb_time, balance, mix, pre_delay, input_filter, treble, bass`) |
| Mic 1 | `e352a52e7f91487e9867c15b0cab32bf` | `outputs/main/controls/{gain,pan,mute}` · effect_0 `{mic, axis, hp}` · effect_1 channel EQ |
| Mic 2 | `a51633695584466c9c4d97869feab064` | same as Mic 1 |
| Room L / R | `56d54cfa2bb64bd49917cca75ba59b0d` / `092624c00bf94c0abcbce6770f14125f` | gain/mute on outputs, effect_0 `{room_mic, room_balance, room_damp, room_hp}` — the app writes both |

Cab, mic model and room mic model are chosen through paneld instead:
`/panel/emperor_state/current_cab_selection` (0–21), `current_mic1_selection`, `current_mic2_selection`,
`current_room_mic_selection`.

Option tables read from the pedal: delay mode `DUAL, XOVR, PING PONG, CHORUS, FLANGER`; 1176 ratio
`4:1, 8:1, 12:1, 20:1, ALL`; LFO `SINE 0/90/180, TRI 0/90/180`; axis `off_axis, on_axis`.
Cab list (app order): … 15 4x12 GB30, 16 UK Vee30, 17 CA Vee30, 18 Super 80, 19 GB25 Punch, 20 GB25 Thick, 21 White 75.
