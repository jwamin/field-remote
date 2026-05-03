import Foundation

/// Holds the live `BLEMIDIManager` from the SwiftUI app so Siri Shortcuts / App Intents can send MIDI on the same connection.
@MainActor
enum ShortcutMIDIBridge {
    private static weak var _midi: BLEMIDIManager?

    static func register(_ midi: BLEMIDIManager) {
        _midi = midi
    }

    static var midi: BLEMIDIManager? { _midi }
}
