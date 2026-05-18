# field-remote

SwiftUI **BLE MIDI** remote for **Teenage Engineering** field gear: **TP-7** (recorder) and **TX-6** (mixer). Scan, connect, and send on-screen controls over Bluetooth. The app infers the device profile from the Bluetooth name; you can override it manually if the name is ambiguous.

Paste or import any MIDI implementation chart (PDF, HTML, or plain text) and the app uses **Apple Intelligence** (on-device, no network) to parse the CC and program change table and generate a fully functional custom control surface — before or after connecting.

Repository: [github.com/jwamin/field-remote](https://github.com/jwamin/field-remote)

## Screenshots

### macOS

| TP-7 | TX-6 |
|------|------|
| ![TP-7 controls](screenshots/tp7.png) | ![TX-6 controls](screenshots/tx6.png) |

### iPhone

| TP-7 | TX-6 |
|------|------|
| ![TP-7 iPhone](screenshots/tp7-iphone.png) | ![TX-6 iPhone](screenshots/tx6-iphone.png) |

## Requirements

- Xcode 16+
- iPhone or iPad (iOS 18.1+) — Apple Intelligence required for chart parsing; BLE controls work without it
- A TP-7, TX-6, or any device that exposes standard **BLE MIDI**

## Features

### Built-in control surfaces
Hardcoded panels matched to the TP-7 and TX-6 MIDI specs — transport, speed, loop, scrub, mix, input gain, and per-track TX-6 controls.

### MIDI chart parser (Apple Intelligence)
Import a MIDI implementation chart from a PDF, HTML file, or paste it as plain text. The on-device language model extracts every CC and program change entry and builds a live control surface matched to that chart:
- **Sliders** for continuous CC ranges
- **Toggles** for on/off parameters
- **Triggers** for momentary or program change sends
- Works **before connecting** — generate the UI offline, then connect

Input is preprocessed before the model sees it: the HTML path uses a full WebKit DOM parse (all tag attributes, inline styles, and every entity handled by the browser engine), with a regex fallback for malformed fragments. A context-window guide in the import sheet shows how many model passes the text requires and offers a one-tap normalize action to trim noise for large documents.

### Siri Shortcuts
App Intents expose BLE MIDI sends to Siri and the Shortcuts app:
- **Send CC** — send a Control Change message (controller 0–127, value 0–127)
- **Send Program Change** — switch program/patch (0–127)

## Project layout

| Path | Role |
|------|------|
| `field-remote.xcodeproj` | Xcode project |
| `BLEMIDIManager.swift` | CoreBluetooth central, BLE MIDI framing, TP-7 / TX-6 helpers |
| `ContentView.swift` | Connection UI, profile routing, TP-7 control panels |
| `TX6ControlsView.swift` | TX-6 control surface |
| `DynamicDeviceView.swift` | Generated control surface (sliders, toggles, triggers) from parsed chart |
| `ChartImportView.swift` | Import sheet — file picker, paste area, context guide, parse trigger |
| `MIDIChartParser.swift` | Text extraction (PDF/HTML/plain) + FoundationModels structured parse |
| `MIDIControlDef.swift` | `@Generable` model types consumed by the parser and stored controls |
| `DeviceControlStore.swift` | UserDefaults persistence keyed by BLE device name |
| `DeviceProfile.swift` | `RemoteDeviceProfile` enum + name-based inference |
| `MIDIAppIntents.swift` | Siri Shortcuts App Intents (CC, program change) |
| `ShortcutMIDIBridge.swift` | Singleton bridge between App Intents and the live BLE manager |
| `FieldRemoteApp.swift` | App entry (`@main`) — owns `BLEMIDIManager`, registers shortcut bridge |

## Building

1. Open `field-remote.xcodeproj` in Xcode.
2. Select your development team. Bluetooth entitlement and usage description are already set.
3. Build and run on a **physical device** — BLE and on-device AI both require real hardware.

> Chart parsing requires Apple Intelligence to be enabled in Settings → Apple Intelligence & Siri. The rest of the app works without it.

## BLE MIDI

Uses the [MIDI over Bluetooth LE](https://www.midi.org/specifications-old/item/bluetooth-le-midi) service (`03B80E5A-EDE8-4B33-A751-6CE34EC4C700`) and characteristic `7772E5DB-3868-4112-A1A9-F2669D106BF3`). Packets follow the standard BLE MIDI framing (1-byte header + 1-byte timestamp + MIDI bytes).

## Siri Shortcuts

The app exposes App Intents for Siri and the Shortcuts app:

- **Send CC** — send a MIDI Control Change message (controller 0–127, value 0–127)
- **Send Program Change** — switch program/patch (0–127)

## License

All rights reserved by the repository owner unless a `LICENSE` file is added.
