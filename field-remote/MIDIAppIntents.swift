import AppIntents
import Foundation

// MARK: - BLE Device Entity

struct BLEDeviceEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "BLE Device"
    static var defaultQuery = BLEDeviceQuery()

    var id: String      // the device display name
    var name: String

    init(name: String) {
        self.id   = name
        self.name = name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

// MARK: - BLE Device Query

struct BLEDeviceQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [BLEDeviceEntity] {
        identifiers.map { BLEDeviceEntity(name: $0) }
    }

    /// Called when the user types in the Shortcuts device search field.
    func entities(matching string: String) async throws -> [BLEDeviceEntity] {
        KnownDevicesStore.deviceNames
            .filter { $0.localizedCaseInsensitiveContains(string) }
            .map    { BLEDeviceEntity(name: $0) }
    }

    /// Pre-populates the Shortcuts composer with previously-connected devices.
    func suggestedEntities() async throws -> [BLEDeviceEntity] {
        KnownDevicesStore.deviceNames.map { BLEDeviceEntity(name: $0) }
    }
}

// MARK: - Errors

enum MIDIIntentError: Error, LocalizedError {
    case notConnected(deviceName: String)
    case wrongDevice(connected: String, expected: String)
    case bluetoothUnavailable

    var errorDescription: String? {
        switch self {
        case .notConnected(let name):
            return "Not connected to \(name). Open Field Remote, connect to \(name), then run the shortcut again."
        case .wrongDevice(let connected, let expected):
            return "\(connected) is connected, but this shortcut targets \(expected). Connect to \(expected) in Field Remote, then try again."
        case .bluetoothUnavailable:
            return "Bluetooth is off or unavailable. Enable Bluetooth and try again."
        }
    }
}

// MARK: - Helpers

private extension MIDIIntentError {
    /// Validates the bridge state against an expected device name and throws if not ready.
    @MainActor
    static func validate(expectedDevice device: BLEDeviceEntity) throws {
        guard let midi = ShortcutMIDIBridge.midi else {
            throw MIDIIntentError.notConnected(deviceName: device.name)
        }
        if midi.connectionState == .bluetoothOff {
            throw MIDIIntentError.bluetoothUnavailable
        }
        guard midi.connectionState == .connected else {
            throw MIDIIntentError.notConnected(deviceName: device.name)
        }
        if let connectedName = ShortcutMIDIBridge.connectedDeviceName,
           connectedName.lowercased() != device.name.lowercased() {
            throw MIDIIntentError.wrongDevice(connected: connectedName, expected: device.name)
        }
    }
}

// MARK: - Send CC

struct SendMIDIControlChangeIntent: AppIntent {
    static var title: LocalizedStringResource = "Send MIDI control change"
    static var description = IntentDescription(
        "Sends a MIDI CC message to a specific BLE MIDI device."
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Device", description: "The BLE MIDI device to send to.")
    var device: BLEDeviceEntity

    @Parameter(title: "MIDI channel", description: "1–16 (MIDI channel 1 is most common).", default: 1)
    var channel: Int

    @Parameter(title: "Controller number", description: "CC number 0–127.", default: 1)
    var controller: Int

    @Parameter(title: "Value", description: "0–127.", default: 64)
    var value: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Send CC to \(\.$device)") {
            \.$channel
            \.$controller
            \.$value
        }
    }

    func perform() async throws -> some IntentResult {
        let ch     = min(max(channel,     1),   16)
        let ccNum  = min(max(controller,  0),  127)
        let val    = min(max(value,        0),  127)
        try await MainActor.run {
            try MIDIIntentError.validate(expectedDevice: device)
            ShortcutMIDIBridge.midi!.cc(UInt8(ccNum), value: UInt8(val), channel: UInt8(ch - 1))
        }
        return .result(dialog: IntentDialog("Sent CC \(ccNum) = \(val) on channel \(ch)."))
    }
}

// MARK: - Send program change

struct SendMIDIProgramChangeIntent: AppIntent {
    static var title: LocalizedStringResource = "Send MIDI program change"
    static var description = IntentDescription(
        "Sends a MIDI program change to a specific BLE MIDI device."
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Device", description: "The BLE MIDI device to send to.")
    var device: BLEDeviceEntity

    @Parameter(title: "MIDI channel", description: "1–16.", default: 1)
    var channel: Int

    @Parameter(title: "Program", description: "Program number 0–127.", default: 0)
    var program: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Send program change to \(\.$device)") {
            \.$channel
            \.$program
        }
    }

    func perform() async throws -> some IntentResult {
        let ch   = min(max(channel,  1),  16)
        let prog = min(max(program,  0), 127)
        try await MainActor.run {
            try MIDIIntentError.validate(expectedDevice: device)
            ShortcutMIDIBridge.midi!.programChange(program: UInt8(prog), channel: UInt8(ch - 1))
        }
        return .result(dialog: IntentDialog("Sent program \(prog) on channel \(ch)."))
    }
}

// MARK: - Shortcuts library

struct FieldRemoteMIDIAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return [
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
            )
        ]
    }
}
