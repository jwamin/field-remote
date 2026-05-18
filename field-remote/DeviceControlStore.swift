import Foundation

/// Persists parsed MIDI control definitions keyed by device name.
enum DeviceControlStore {
    private static let keyPrefix = "field_remote_controls_"

    static func controls(for deviceName: String) -> [MIDIControlDef] {
        guard let data = UserDefaults.standard.data(forKey: key(deviceName)),
              let defs = try? JSONDecoder().decode([MIDIControlDef].self, from: data)
        else { return [] }
        return defs
    }

    static func save(_ controls: [MIDIControlDef], for deviceName: String) {
        let data = try? JSONEncoder().encode(controls)
        UserDefaults.standard.set(data, forKey: key(deviceName))
    }

    static func clear(for deviceName: String) {
        UserDefaults.standard.removeObject(forKey: key(deviceName))
    }

    private static func key(_ deviceName: String) -> String {
        keyPrefix + deviceName.lowercased()
    }
}
