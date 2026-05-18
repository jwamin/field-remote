import Foundation

// MARK: - Known devices store

/// Persists BLE device names seen during successful connections so the Shortcuts
/// composer can offer them as selectable options.
enum KnownDevicesStore {
    private nonisolated static var key: String { "field_remote_known_devices" }

    nonisolated static var deviceNames: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    nonisolated static func record(name: String) {
        var names = deviceNames
        guard !names.contains(name) else { return }
        names.insert(name, at: 0)           // most-recently-seen first
        UserDefaults.standard.set(names, forKey: key)
    }
}

// MARK: - Bridge

/// Holds the live `BLEMIDIManager` so App Intents can send MIDI on the same connection.
@MainActor
enum ShortcutMIDIBridge {
    private static weak var _midi: BLEMIDIManager?

    static func register(_ midi: BLEMIDIManager) {
        _midi = midi
    }

    static var midi: BLEMIDIManager? { _midi }

    /// Display name of the currently-connected peripheral, or nil if not connected.
    static var connectedDeviceName: String? { _midi?.connectedDeviceName }
}
