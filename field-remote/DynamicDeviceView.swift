import SwiftUI

// MARK: - Root

struct DynamicDeviceView: View {
    let controls: [MIDIControlDef]
    let midi: BLEMIDIManager

    private var channels: [Int] {
        Array(Set(controls.map(\.channel))).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(channels, id: \.self) { ch in
                let chControls = controls.filter { $0.channel == ch }
                DynamicSectionHeader(title: "ch \(ch)")
                ForEach(chControls) { control in
                    DynamicControlRow(control: control, midi: midi)
                    Divider().padding(.leading)
                }
            }
            Spacer(minLength: 32)
        }
    }
}

// MARK: - Section header

private struct DynamicSectionHeader: View {
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

// MARK: - Control row (dispatches on style)

private struct DynamicControlRow: View {
    let control: MIDIControlDef
    let midi: BLEMIDIManager

    var body: some View {
        // Program change is always a trigger regardless of the parsed style hint.
        switch control.messageType {
        case .programChange:
            PCTriggerRow(control: control, midi: midi)
        case .cc:
            switch control.controlStyle {
            case .slider:  CCSliderRow(control: control, midi: midi)
            case .toggle:  CCToggleRow(control: control, midi: midi)
            case .trigger: CCTriggerRow(control: control, midi: midi)
            }
        }
    }
}

// MARK: - CC slider

private struct CCSliderRow: View {
    let control: MIDIControlDef
    let midi: BLEMIDIManager

    @State private var value: Double

    init(control: MIDIControlDef, midi: BLEMIDIManager) {
        self.control = control
        self.midi    = midi
        _value = State(initialValue: Double(control.minValue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(control.name)
                    .font(.system(.caption, design: .monospaced))
                Spacer()
                Text("\(Int(value))")
                    .font(.system(.caption, design: .monospaced).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: $value,
                in: Double(control.minValue)...Double(max(control.minValue + 1, control.maxValue)),
                step: 1
            )
            .onChange(of: value) { _, v in
                midi.cc(UInt8(control.number), value: UInt8(v), channel: UInt8(control.channel - 1))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - CC toggle

private struct CCToggleRow: View {
    let control: MIDIControlDef
    let midi: BLEMIDIManager

    @State private var isOn = false

    var body: some View {
        HStack {
            Text(control.name)
                .font(.system(.caption, design: .monospaced))
            Spacer()
            Button {
                isOn.toggle()
                let v = isOn ? UInt8(control.maxValue) : UInt8(control.minValue)
                midi.cc(UInt8(control.number), value: v, channel: UInt8(control.channel - 1))
            } label: {
                Text(isOn ? "on" : "off")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 44, height: 28)
                    .background(isOn ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

// MARK: - CC trigger (momentary)

private struct CCTriggerRow: View {
    let control: MIDIControlDef
    let midi: BLEMIDIManager

    @GestureState private var isPressed = false

    var body: some View {
        HStack {
            Text(control.name)
                .font(.system(.caption, design: .monospaced))
            Spacer()
            Text("hold")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 60, height: 28)
                .background(isPressed ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isPressed) { _, state, _ in state = true }
                        .onChanged { _ in
                            if !isPressed {
                                midi.cc(UInt8(control.number), value: UInt8(control.maxValue),
                                        channel: UInt8(control.channel - 1))
                            }
                        }
                        .onEnded { _ in
                            midi.cc(UInt8(control.number), value: UInt8(control.minValue),
                                    channel: UInt8(control.channel - 1))
                        }
                )
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

// MARK: - Program change trigger

private struct PCTriggerRow: View {
    let control: MIDIControlDef
    let midi: BLEMIDIManager

    @State private var sent = false

    var body: some View {
        HStack {
            Text(control.name)
                .font(.system(.caption, design: .monospaced))
            Spacer()
            Button {
                midi.programChange(program: UInt8(control.number),
                                   channel: UInt8(control.channel - 1))
                withAnimation(.easeOut(duration: 0.6)) { sent = true }
                Task {
                    try? await Task.sleep(for: .seconds(0.6))
                    sent = false
                }
            } label: {
                Text(sent ? "sent" : "send")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 60, height: 28)
                    .background(sent ? Color.green.opacity(0.2) : Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}
