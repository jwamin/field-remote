import AppIntents
import Foundation

// MARK: - Errors

enum MIDIIntentError: Error, LocalizedError {
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected over Bluetooth MIDI. Open Field Remote, connect to your device, then run the shortcut again."
        }
    }
}

// MARK: - Send CC

struct SendMIDIControlChangeIntent: AppIntent {
    static var title: LocalizedStringResource = "Send MIDI control change"
    static var description = IntentDescription(
        "Sends a MIDI CC on the current BLE MIDI connection (same as in the app)."
    )
    /// Opening the app improves reliability of CoreBluetooth when the app was not active.
    static var openAppWhenRun: Bool = true

    @Parameter(title: "MIDI channel", description: "1–16 (MIDI channel 1 is most common).", default: 1)
    var channel: Int

    @Parameter(title: "Controller number", description: "CC number 0–127.", default: 1)
    var controller: Int

    @Parameter(title: "Value", description: "0–127.", default: 64)
    var value: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Send CC on channel \(\.$channel)") {
            \.$controller
            \.$value
        }
    }

    func perform() async throws -> some IntentResult {
        let ch = min(max(channel, 1), 16)
        let ccNum = min(max(controller, 0), 127)
        let val = min(max(value, 0), 127)
        try await MainActor.run {
            guard let midi = ShortcutMIDIBridge.midi else { throw MIDIIntentError.notConnected }
            guard midi.connectionState == .connected else { throw MIDIIntentError.notConnected }
            midi.cc(UInt8(ccNum), value: UInt8(val), channel: UInt8(ch - 1))
        }
        return .result(dialog: IntentDialog("Sent CC \(ccNum) = \(val) on channel \(ch)."))
    }
}

// MARK: - Send program change

struct SendMIDIProgramChangeIntent: AppIntent {
    static var title: LocalizedStringResource = "Send MIDI program change"
    static var description = IntentDescription(
        "Sends a MIDI program change on the current BLE MIDI connection."
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "MIDI channel", description: "1–16.", default: 1)
    var channel: Int

    @Parameter(title: "Program", description: "Program number 0–127.", default: 0)
    var program: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Send program change on channel \(\.$channel)") {
            \.$program
        }
    }

    func perform() async throws -> some IntentResult {
        let ch = min(max(channel, 1), 16)
        let prog = min(max(program, 0), 127)
        try await MainActor.run {
            guard let midi = ShortcutMIDIBridge.midi else { throw MIDIIntentError.notConnected }
            guard midi.connectionState == .connected else { throw MIDIIntentError.notConnected }
            midi.programChange(program: UInt8(prog), channel: UInt8(ch - 1))
        }
        return .result(dialog: IntentDialog("Sent program \(prog) on channel \(ch)."))
    }
}

// MARK: - Shortcuts library

struct FieldRemoteMIDIAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(
                intent: SendMIDIControlChangeIntent(),
                phrases: [
                    "Send MIDI CC in \(.applicationName)",
                    "Send control change in \(.applicationName)",
                ],
                shortTitle: "Send CC",
                systemImageName: "slider.horizontal.3"
            ),
            AppShortcut(
                intent: SendMIDIProgramChangeIntent(),
                phrases: [
                    "Send MIDI program change in \(.applicationName)",
                    "Send program change in \(.applicationName)",
                ],
                shortTitle: "Send PC",
                systemImageName: "pianokeys"
            ),
        ]
    }
}
