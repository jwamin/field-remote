# TP7 Remote

SwiftUI companion for the **Teenage Engineering TP-7** field recorder. Connect over **Bluetooth LE MIDI**, pick your device, and use on-screen controls for transport, speed, looping, scrub, mix, and input routing.

## Requirements

- Xcode 15+ (SwiftUI targets recent iOS; adjust the deployment target in the project if needed)
- An iPhone or iPad with Bluetooth enabled
- A TP-7 (or another peripheral exposing the standard BLE MIDI service) in range

## Project layout

| Path | Role |
|------|------|
| `TP7Remote/BLEMIDIManager.swift` | CoreBluetooth central, BLE MIDI framing, TP-7-oriented MIDI helpers |
| `TP7Remote/ContentView.swift` | Main UI: connection, transport, speed, loop, scrub, mix, input |
| `TP7Remote/TP7RemoteApp.swift` | App entry point |

## Building

1. Open `TP7Remote.xcodeproj` in Xcode.
2. Select your development team for signing (and enable the **Bluetooth** capability if Xcode prompts you).
3. Build and run on a physical device (Bluetooth is not available in the simulator for real hardware workflows).

## BLE MIDI

The app scans for the [MIDI over Bluetooth Low Energy](https://www.midi.org/specifications-old/item/bluetooth-le-midi) service (`03B80E5A-EDE8-4B33-A751-6CE34EC4C700`) and sends packets on the characteristic `7772E5DB-3868-4112-A1A9-F2669D106BF3`.

## License

Unless you add a `LICENSE` file, all rights are reserved by the repository owner. Add a license here if you intend to open-source the code under specific terms.
