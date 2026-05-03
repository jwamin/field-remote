import Foundation

/// Which hardware UI / MIDI mapping to use after connecting over BLE MIDI.
enum RemoteDeviceProfile: String, CaseIterable, Identifiable {
    case tp7
    case tx6

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .tp7: return "tp-7"
        case .tx6: return "tx-6"
        }
    }

    var navigationTitle: String {
        switch self {
        case .tp7: return "tp-7 remote"
        case .tx6: return "tx-6 remote"
        }
    }

    static func infer(fromName name: String?) -> RemoteDeviceProfile? {
        guard let n = name?.lowercased() else { return nil }
        if n.contains("tx-6") || n.contains("tx6") { return .tx6 }
        if n.contains("tp-7") || n.contains("tp7") { return .tp7 }
        return nil
    }
}
