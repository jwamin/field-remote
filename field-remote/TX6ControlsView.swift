import SwiftUI

/// BLE MIDI controls for Teenage Engineering TX-6 (incoming MIDI map).
struct TX6ControlsView: View {
    @ObservedObject var midi: BLEMIDIManager

    @State private var track = 1
    @State private var vol: Double = 100
    @State private var pan: Double = 64
    @State private var gain: Double = 64
    @State private var seqPattern: Double = 0
    @State private var trackMute = false
    @State private var filter: Double = 64
    @State private var eqH: Double = 64
    @State private var eqM: Double = 64
    @State private var eqL: Double = 64
    @State private var comp: Double = 0
    @State private var wave: Double = 0
    @State private var synthFreq: Double = 64
    @State private var synthLen: Double = 64
    @State private var detune: Double = 64
    @State private var fx1Send: Double = 0
    @State private var auxSend: Double = 0
    @State private var aux2Send: Double = 0

    @State private var mainVol: Double = 100
    @State private var auxVol: Double = 100
    @State private var cueVol: Double = 100
    @State private var localOn = true
    @State private var tempoOffset: Double = 0
    @State private var fxBus1On = false
    @State private var fxBus2On = false
    @State private var fx1Engine: Double = 0
    @State private var fx2Engine: Double = 0
    @State private var fx1p1: Double = 64
    @State private var fx1p2: Double = 64
    @State private var fx1p3: Double = 64
    @State private var fx2p1: Double = 64
    @State private var fx2p2: Double = 64
    @State private var fx2p3: Double = 64
    @State private var fxIReturn: Double = 64
    @State private var fx2TrackSel: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            trackPicker
            trackSliders
            Divider().padding(.vertical, 1)
            masterSection
            Divider().padding(.vertical, 1)
            fxSection
            Divider().padding(.vertical, 1)
            transportSection
            Spacer(minLength: 24)
        }
        .onChange(of: track) { _, _ in syncTrackStateFromMidiDefaults() }
        .onAppear { syncTrackStateFromMidiDefaults() }
    }

    private var trackPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeaderTX6(title: "track \(track)")
            Picker("Track", selection: $track) {
                ForEach(1...6, id: \.self) { t in
                    Text("\(t)").tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private var trackSliders: some View {
        VStack(spacing: 10) {
            TX6SliderRow(title: "volume", value: $vol) { midi.tx6TrackVolume(UInt8($0), track: track) }
            TX6SliderRow(title: "pan / balance", value: $pan) { midi.tx6TrackPan(UInt8($0), track: track) }
            TX6SliderRow(title: "gain", value: $gain) { midi.tx6TrackGain(UInt8($0), track: track) }
            TX6SliderRow(title: "seq pattern", value: $seqPattern) { midi.tx6SeqPattern(UInt8($0), track: track) }
            HStack {
                Text("mute / solo")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: $trackMute)
                    .labelsHidden()
                    .onChange(of: trackMute) { _, v in midi.tx6TrackMuteSolo(v, track: track) }
            }
            .padding(.horizontal)
            TX6SliderRow(title: "filter", value: $filter) { midi.tx6Filter(UInt8($0), track: track) }
            TX6SliderRow(title: "EQ high", value: $eqH) { midi.tx6EQHigh(UInt8($0), track: track) }
            TX6SliderRow(title: "EQ mid", value: $eqM) { midi.tx6EQMid(UInt8($0), track: track) }
            TX6SliderRow(title: "EQ low", value: $eqL) { midi.tx6EQLow(UInt8($0), track: track) }
            TX6SliderRow(title: "compressor", value: $comp) { midi.tx6Compressor(UInt8($0), track: track) }
            TX6SliderRow(title: "synth wave", value: $wave) { midi.tx6SynthWaveform(UInt8($0), track: track) }
            TX6SliderRow(title: "synth freq", value: $synthFreq) { midi.tx6SynthFrequency(UInt8($0), track: track) }
            TX6SliderRow(title: "synth length", value: $synthLen) { midi.tx6SynthLength(UInt8($0), track: track) }
            TX6SliderRow(title: "synth detune", value: $detune) { midi.tx6SynthDetune(UInt8($0), track: track) }
            TX6SliderRow(title: "FX I send", value: $fx1Send) { midi.tx6FXISend(UInt8($0), track: track) }
            TX6SliderRow(title: "aux send", value: $auxSend) { midi.tx6AuxSend(UInt8($0), track: track) }
            TX6SliderRow(title: "aux II send", value: $aux2Send) { midi.tx6Aux2Send(UInt8($0), track: track) }
        }
        .padding(.bottom, 8)
    }

    private var masterSection: some View {
        VStack(spacing: 10) {
            SectionHeaderTX6(title: "master (ch 7)")
            TX6SliderRow(title: "main volume", value: $mainVol) { midi.tx6MainVolume(UInt8($0)) }
            TX6SliderRow(title: "aux volume", value: $auxVol) { midi.tx6AuxVolume(UInt8($0)) }
            TX6SliderRow(title: "cue volume", value: $cueVol) { midi.tx6CueVolume(UInt8($0)) }
            HStack {
                Text("local control")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle(localOn ? "on" : "off", isOn: $localOn)
                    .font(.system(.caption, design: .monospaced))
                    .onChange(of: localOn) { _, v in midi.tx6LocalControl(v) }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

    private var fxSection: some View {
        VStack(spacing: 10) {
            SectionHeaderTX6(title: "FX I / II (ch 8–9)")
            HStack {
                Text("FX I enable")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: $fxBus1On)
                    .labelsHidden()
            }
            .padding(.horizontal)
            HStack {
                Text("FX II enable")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: $fxBus2On)
                    .labelsHidden()
            }
            .padding(.horizontal)
            .onChange(of: fxBus1On) { _, _ in pushFXEnables() }
            .onChange(of: fxBus2On) { _, _ in pushFXEnables() }

            TX6SliderRow(title: "FX I engine", value: $fx1Engine) { midi.tx6FXEngine(UInt8($0), fxSlot: 1) }
            TX6SliderRow(title: "FX II engine", value: $fx2Engine) { midi.tx6FXEngine(UInt8($0), fxSlot: 2) }
            TX6SliderRow(title: "FX I param 1", value: $fx1p1) { midi.tx6FXParam1(UInt8($0), fxSlot: 1) }
            TX6SliderRow(title: "FX I param 2", value: $fx1p2) { midi.tx6FXParam2(UInt8($0), fxSlot: 1) }
            TX6SliderRow(title: "FX I param 3", value: $fx1p3) { midi.tx6FXParam3(UInt8($0), fxSlot: 1) }
            TX6SliderRow(title: "FX II param 1", value: $fx2p1) { midi.tx6FXParam1(UInt8($0), fxSlot: 2) }
            TX6SliderRow(title: "FX II param 2", value: $fx2p2) { midi.tx6FXParam2(UInt8($0), fxSlot: 2) }
            TX6SliderRow(title: "FX II param 3", value: $fx2p3) { midi.tx6FXParam3(UInt8($0), fxSlot: 2) }
            TX6SliderRow(title: "FX I return", value: $fxIReturn) { midi.tx6FXIReturnLevel(UInt8($0)) }
            TX6SliderRow(title: "FX II track sel.", value: $fx2TrackSel) { midi.tx6FX2TrackSelect(UInt8($0)) }
        }
        .padding(.bottom, 8)
    }

    private var transportSection: some View {
        VStack(spacing: 12) {
            SectionHeaderTX6(title: "transport")
            Button {
                midi.tx6StartStopPulse()
            } label: {
                Text("start / stop")
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            VStack(alignment: .leading, spacing: 4) {
                Text("tempo relative  (−64 … +63)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                Slider(value: $tempoOffset, in: -64...63, step: 1)
                    .onChange(of: tempoOffset) { _, v in midi.tx6TempoRelative(offset: Int(v)) }
                    .padding(.horizontal)
                HStack {
                    Text("−64").font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(Int(tempoOffset))")
                        .font(.system(.caption2, design: .monospaced))
                    Spacer()
                    Text("+63").font(.system(.caption2, design: .monospaced)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
            }
            Text("CC on/off: 0–63 = off, 64–127 = on (per TX-6 reference).")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        }
    }

    private func pushFXEnables() {
        midi.tx6FXBusEnable(fx1: fxBus1On, fx2: fxBus2On)
    }

    /// Per-track UI state is local only; switching track resets to sensible defaults until moved.
    private func syncTrackStateFromMidiDefaults() {
        vol = 100
        pan = 64
        gain = 64
        seqPattern = 0
        trackMute = false
        filter = 64
        eqH = 64
        eqM = 64
        eqL = 64
        comp = 0
        wave = 0
        synthFreq = 64
        synthLen = 64
        detune = 64
        fx1Send = 0
        auxSend = 0
        aux2Send = 0
    }
}

private struct TX6SliderRow: View {
    let title: String
    @Binding var value: Double
    let send: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value))")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)
            Slider(value: $value, in: 0...127, step: 1)
                .onChange(of: value) { _, v in send(v) }
                .padding(.horizontal)
        }
    }
}

private struct SectionHeaderTX6: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

#Preview("TX-6 controls") {
    ScrollView {
        TX6ControlsView(midi: BLEMIDIManager())
    }
}

#Preview("TX-6 iPhone") {
    NavigationStack {
        ScrollView {
            TX6ControlsView(midi: BLEMIDIManager())
        }
        .navigationTitle("tx-6")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    .frame(width: 390, height: 844)
}
