import SwiftUI

@main
struct FieldRemoteApp: App {
    @StateObject private var midi = BLEMIDIManager()

    var body: some Scene {
        WindowGroup {
            ContentView(midi: midi)
                .onAppear {
                    ShortcutMIDIBridge.register(midi)
                }
        }
    }
}
