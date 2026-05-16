import SwiftUI
import CoreBluetooth
// MARK: - Root

struct ContentView: View {
    @ObservedObject var midi: BLEMIDIManager
    @State private var showDevicePicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ConnectionBar(midi: midi, showPicker: $showDevicePicker)
                        .padding(.bottom, 1)

                    if midi.connectionState == .connected {
                        if midi.inferredDeviceProfile == nil {
                            UnknownProfileBar(midi: midi)
                        }
                        Group {
                            switch midi.effectiveDeviceProfile {
                            case .tp7:
                                TP7ConnectedPanels(midi: midi)
                            case .tx6:
                                TX6ControlsView(midi: midi)
                            }
                        }
                    } else {
                        DisconnectedPrompt(state: midi.connectionState)
                    }
                }
            }
            .navigationTitle(midi.connectionState == .connected
                             ? midi.effectiveDeviceProfile.navigationTitle
                             : "field remote")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(midi.connectionState == .connected
                         ? midi.effectiveDeviceProfile.navigationTitle
                         : "field remote")
                        .font(.system(.headline, design: .monospaced))
                }
            }
        }
        .sheet(isPresented: $showDevicePicker) {
            DevicePickerSheet(midi: midi, isPresented: $showDevicePicker)
        }
    }
}

// MARK: - Connection bar

private struct ConnectionBar: View {
    @ObservedObject var midi: BLEMIDIManager
    @Binding var showPicker: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: primaryAction) {
                Text(buttonLabel)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .disabled(midi.connectionState == .bluetoothOff)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var indicatorColor: Color {
        switch midi.connectionState {
        case .connected:   .green
        case .connecting:  .yellow
        case .scanning:    .blue
        default:           .gray
        }
    }

    private var statusLabel: String {
        switch midi.connectionState {
        case .disconnected:  "not connected"
        case .bluetoothOff:  "bluetooth off"
        case .scanning:      "scanning…"
        case .connecting:    "connecting…"
        case .connected:     midi.connectedDevice?.name ?? "connected"
        }
    }

    private var buttonLabel: String {
        switch midi.connectionState {
        case .connected:  "disconnect"
        case .scanning:   "cancel"
        default:          "scan"
        }
    }

    private func primaryAction() {
        switch midi.connectionState {
        case .connected:
            midi.disconnect()
        case .scanning:
            midi.stopScanning()
        default:
            midi.startScanning()
            showPicker = true
        }
    }
}

// MARK: - Device picker sheet

private struct DevicePickerSheet: View {
    @ObservedObject var midi: BLEMIDIManager
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                if midi.discoveredDevices.isEmpty {
                    HStack {
                        ProgressView()
                        Text("scanning for ble midi devices…")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                    }
                } else {
                    ForEach(midi.discoveredDevices, id: \.identifier) { device in
                        Button {
                            midi.connect(device)
                            isPresented = false
                        } label: {
                            HStack {
                                Text(device.name ?? device.identifier.uuidString.prefix(8).lowercased())
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("devices")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        midi.stopScanning()
                        isPresented = false
                    }
                    .font(.system(.body, design: .monospaced))
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Profile fallback (name did not match TP-7 / TX-6)

private struct UnknownProfileBar: View {
    @ObservedObject var midi: BLEMIDIManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("could not detect device from name — choose profile (default is TP-7).")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack {
                Text("profile")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("automatic (TP-7 if unsure)") {
                        midi.deviceProfileOverride = nil
                    }
                    Button("TP-7") { midi.deviceProfileOverride = .tp7 }
                    Button("TX-6") { midi.deviceProfileOverride = .tx6 }
                } label: {
                    Text(profileLabel)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.12))
    }

    private var profileLabel: String {
        if let o = midi.deviceProfileOverride { return o.shortTitle }
        return "tp-7 (default)"
    }
}

// MARK: - TP-7 panels

private struct TP7ConnectedPanels: View {
    @ObservedObject var midi: BLEMIDIManager

    var body: some View {
        VStack(spacing: 0) {
            TransportSection(midi: midi)
            Divider().padding(.vertical, 1)
            SpeedSection(midi: midi)
            Divider().padding(.vertical, 1)
            LoopSection(midi: midi)
            Divider().padding(.vertical, 1)
            ScrubSection(midi: midi)
            Divider().padding(.vertical, 1)
            MixSection(midi: midi)
            Divider().padding(.vertical, 1)
            InputSection(midi: midi)
            Spacer(minLength: 32)
        }
    }
}

// MARK: - Disconnected prompt

private struct DisconnectedPrompt: View {
    let state: BLEMIDIManager.ConnectionState

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            Image(systemName: state == .bluetoothOff ? "bluetooth.slash" : "wave.3.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(state == .bluetoothOff
                 ? "enable bluetooth to continue"
                 : "scan to connect to your tp-7 or tx-6")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Section header helper

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }
}

// MARK: - Transport

private struct TransportSection: View {
    @ObservedObject var midi: BLEMIDIManager
    @State private var recOn     = false
    @State private var cueRecOn  = false
    @State private var cueNote: UInt8 = 0
    @State private var noteHeld  = false

    var body: some View {
        SectionHeader(title: "transport")
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                TransportButton(label: "play", systemImage: "play.fill") {
                    midi.scrubPlay()
                }
                TransportButton(label: "pause", systemImage: "pause.fill") {
                    midi.scrubPause()
                }
            }
            .padding(.horizontal)

            // Rec + Cue Rec toggles
            HStack(spacing: 12) {
                ToggleButton(label: "rec", isOn: $recOn) { on in
                    midi.rec(on)
                }
                ToggleButton(label: "cue rec", isOn: $cueRecOn) { on in
                    midi.cueRec(on)
                }
            }
            .padding(.horizontal)

            // Cue marker trigger
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("cue marker")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("note \(cueNote)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                // Note selector
                HStack(spacing: 6) {
                    ForEach(0..<8) { i in
                        let note = UInt8(i)
                        Button {
                            cueNote = note
                        } label: {
                            Text("\(i)")
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .background(cueNote == note ? Color.accentColor.opacity(0.25) : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(cueNote == note ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                // Hold to trigger
                Text("hold to trigger")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(noteHeld ? .primary : .tertiary)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(noteHeld ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !noteHeld {
                                    noteHeld = true
                                    midi.noteOn(cueNote)
                                }
                            }
                            .onEnded { _ in
                                noteHeld = false
                                midi.noteOff(cueNote)
                            }
                    )
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Speed (pitch bend)

private struct SpeedSection: View {
    @ObservedObject var midi: BLEMIDIManager
    @State private var speed: Double = 0

    var body: some View {
        SectionHeader(title: "playback speed")
        VStack(spacing: 6) {
            Slider(value: $speed, in: -8192...8191, step: 1)
                .onChange(of: speed) { _, v in midi.pitchBend(Int(v)) }
                .padding(.horizontal)
            HStack {
                Text("-8192")
                Spacer()
                Text(speed == 0 ? "0" : (speed > 0 ? "+\(Int(speed))" : "\(Int(speed))"))
                    .foregroundStyle(speed == 0 ? .tertiary : .primary)
                Spacer()
                Text("+8191")
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.horizontal)
            Button("reset") {
                speed = 0
                midi.pitchBend(0)
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Loop

private struct LoopSection: View {
    @ObservedObject var midi: BLEMIDIManager
    @State private var mode = 0

    var body: some View {
        SectionHeader(title: "loop")
        Picker("loop", selection: $mode) {
            Text("off").tag(0)
            Text("in").tag(1)
            Text("out").tag(2)
        }
        .pickerStyle(.segmented)
        .font(.system(.body, design: .monospaced))
        .padding(.horizontal)
        .padding(.bottom, 8)
        .onChange(of: mode) { _, v in midi.loopMode(UInt8(v)) }
    }
}

// MARK: - Scrub (FF/Rew)

private struct ScrubSection: View {
    @ObservedObject var midi: BLEMIDIManager
    // MIDI value 0-127; 64 = pause, 68 (+4) = play
    @State private var scrubMidi: Double = Double(BLEMIDIManager.scrubPauseValue)

    var displayValue: Int { Int(scrubMidi) - 64 }

    private var statusLabel: String {
        let v = UInt8(scrubMidi)
        if v == BLEMIDIManager.scrubPauseValue { return "pause" }
        if v == BLEMIDIManager.scrubPlayValue { return "play" }
        return displayValue > 0 ? "+\(displayValue)" : "\(displayValue)"
    }

    var body: some View {
        SectionHeader(title: "ffwd / rew")
        VStack(spacing: 6) {
            Slider(value: $scrubMidi, in: 0...127, step: 1)
                .onChange(of: scrubMidi) { _, v in midi.scrub(UInt8(v)) }
                .padding(.horizontal)
            HStack {
                Text("-64")
                Spacer()
                Text(statusLabel)
                    .foregroundStyle(
                        scrubMidi == Double(BLEMIDIManager.scrubPauseValue)
                        || scrubMidi == Double(BLEMIDIManager.scrubPlayValue)
                        ? .tertiary : .primary
                    )
                Spacer()
                Text("+63")
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.horizontal)
            HStack(spacing: 12) {
                Button("play") {
                    scrubMidi = Double(BLEMIDIManager.scrubPlayValue)
                    midi.scrubPlay()
                }
                .frame(maxWidth: .infinity)
                Button("pause") {
                    scrubMidi = Double(BLEMIDIManager.scrubPauseValue)
                    midi.scrubPause()
                }
                .frame(maxWidth: .infinity)
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Mix (6 channels)

private struct MixSection: View {
    @ObservedObject var midi: BLEMIDIManager
    @State private var volumes: [Double] = Array(repeating: 100, count: 6)
    @State private var mutes:   [Bool]   = Array(repeating: false, count: 6)

    var body: some View {
        SectionHeader(title: "mix")
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                ForEach(1...6, id: \.self) { ch in
                    Text("ch\(ch)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 4)

            // Volume faders
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<6) { i in
                    VStack(spacing: 4) {
                        Text("\(Int(volumes[i]))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        VerticalSlider(value: $volumes[i], in: 0...127)
                            .frame(height: 120)
                            .onChange(of: volumes[i]) { _, v in
                                midi.mixVolume(UInt8(v), channel: i + 1)
                            }
                        // Mute button
                        Button {
                            mutes[i].toggle()
                            midi.mixMute(mutes[i], channel: i + 1)
                        } label: {
                            Text("m")
                                .font(.system(.caption, design: .monospaced))
                                .frame(width: 28, height: 22)
                                .background(mutes[i] ? Color.orange.opacity(0.8) : Color.secondary.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Input gain (3 channels)

private struct InputSection: View {
    @ObservedObject var midi: BLEMIDIManager
    @State private var gains: [Double] = Array(repeating: 64, count: 3)

    var body: some View {
        SectionHeader(title: "input gain")
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<3) { i in
                VStack(spacing: 4) {
                    Text("ch\(i + 1)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text("\(Int(gains[i]))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    VerticalSlider(value: $gains[i], in: 0...127)
                        .frame(height: 100)
                        .onChange(of: gains[i]) { _, v in
                            midi.inputGain(UInt8(v), channel: i + 1)
                        }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
    }
}

// MARK: - Transport button (momentary)

private struct TransportButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.system(.body, design: .monospaced))
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.secondary.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Toggle button

private struct ToggleButton: View {
    let label: String
    @Binding var isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Button {
            isOn.toggle()
            onChange(isOn)
        } label: {
            Text(label)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(isOn ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Vertical slider

private struct VerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    init(value: Binding<Double>, in range: ClosedRange<Double>) {
        _value = value
        self.range = range
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Track
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 4)
                    .frame(maxWidth: .infinity)

                // Fill
                let fillFraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                Capsule()
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 4, height: max(4, geo.size.height * fillFraction))
                    .frame(maxWidth: .infinity)

                // Thumb
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 16, height: 16)
                    .frame(maxWidth: .infinity)
                    .offset(y: -geo.size.height * fillFraction + 8)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = 1 - (drag.location.y / geo.size.height)
                        value = (range.lowerBound + fraction * (range.upperBound - range.lowerBound))
                            .clamped(to: range)
                    }
            )
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Preview

#Preview("disconnected") {
    ContentView(midi: BLEMIDIManager())
}

#Preview("TP-7 controls") {
    ScrollView {
        TP7ConnectedPanels(midi: BLEMIDIManager())
    }
}

#Preview("TP-7 iPhone") {
    NavigationStack {
        ScrollView {
            TP7ConnectedPanels(midi: BLEMIDIManager())
        }
        .navigationTitle("tp-7")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    .frame(width: 390, height: 844)
}
