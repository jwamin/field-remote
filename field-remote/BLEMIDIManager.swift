import CoreBluetooth
import Combine

class BLEMIDIManager: NSObject, ObservableObject {
    static let midiServiceUUID = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
    static let midiCharUUID    = CBUUID(string: "7772E5DB-3868-4112-A1A9-F2669D106BF3")

    enum ConnectionState: String {
        case disconnected, bluetoothOff, scanning, connecting, connected
    }

    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectedDevice: CBPeripheral?
    @Published var connectionState: ConnectionState = .disconnected

    /// Set from peripheral / advertisement name when possible.
    @Published private(set) var inferredDeviceProfile: RemoteDeviceProfile?
    /// User-chosen profile when inference fails (or to override).
    @Published var deviceProfileOverride: RemoteDeviceProfile?

    private var central: CBCentralManager!
    private var midiChar: CBCharacteristic?
    private var advertisementLocalNames: [UUID: String] = [:]

    /// Profile used for UI and MIDI mapping.
    var effectiveDeviceProfile: RemoteDeviceProfile {
        deviceProfileOverride ?? inferredDeviceProfile ?? .tp7
    }

    /// Best available display name for the currently-connected peripheral.
    var connectedDeviceName: String? {
        guard let device = connectedDevice else { return nil }
        return device.name ?? advertisementLocalNames[device.identifier]
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScanning() {
        guard central.state == .poweredOn else { return }
        discoveredDevices = []
        connectionState = .scanning
        central.scanForPeripherals(withServices: [Self.midiServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScanning() {
        central.stopScan()
        if connectionState == .scanning { connectionState = .disconnected }
    }

    func connect(_ peripheral: CBPeripheral) {
        stopScanning()
        connectionState = .connecting
        central.connect(peripheral)
    }

    func disconnect() {
        guard let d = connectedDevice else { return }
        advertisementLocalNames.removeValue(forKey: d.identifier)
        central.cancelPeripheralConnection(d)
    }

    // MARK: - MIDI transmission

    func send(_ bytes: [UInt8]) {
        guard let char = midiChar, let device = connectedDevice else { return }
        // BLE MIDI packet: 1-byte header + 1-byte timestamp + MIDI bytes
        let ts = UInt16(UInt64(Date().timeIntervalSince1970 * 1000) & 0x3FF)
        let header    = UInt8(0x80 | (ts >> 7 & 0x3F))
        let timestamp = UInt8(0x80 | (ts & 0x7F))
        let packet = Data([header, timestamp] + bytes)
        device.writeValue(packet, for: char, type: .withoutResponse)
    }

    // MARK: - TP-7 MIDI helpers

    /// Cue marker – note number selects the marker
    func noteOn(_ note: UInt8)  { send([0x90, note & 0x7F, 0x7F]) }
    func noteOff(_ note: UInt8) { send([0x80, note & 0x7F, 0x00]) }

    /// Playback speed – value -8192...+8191
    func pitchBend(_ value: Int) {
        let v   = (value + 8192).clamped(to: 0...16383)
        let lsb = UInt8(v & 0x7F)
        let msb = UInt8(v >> 7 & 0x7F)
        send([0xE0, lsb, msb])
    }

    /// CC on a given 0-based channel (0 = ch 1)
    func cc(_ number: UInt8, value: UInt8, channel: UInt8 = 0) {
        send([0xB0 | (channel & 0x0F), number, value & 0x7F])
    }

    /// Program change on a given 0-based channel (0 = ch 1)
    func programChange(program: UInt8, channel: UInt8 = 0) {
        send([0xC0 | (channel & 0x0F), program & 0x7F])
    }

    // Convenience wrappers matching the TP-7 MIDI spec

    /// Mix volume  CC7  ch 1-6 (pass channel 1-6)
    func mixVolume(_ value: UInt8, channel: Int) {
        cc(7, value: value, channel: UInt8(channel - 1))
    }

    /// Input gain  CC9  ch 1-3
    func inputGain(_ value: UInt8, channel: Int) {
        cc(9, value: value, channel: UInt8(channel - 1))
    }

    /// Rec toggle  CC14
    func rec(_ on: Bool)     { cc(14, value: on ? 127 : 0) }

    /// Cue rec mode  CC16
    func cueRec(_ on: Bool)  { cc(16, value: on ? 127 : 0) }

    /// Loop mode  CC17  0=off 1=in 2=out
    func loopMode(_ mode: UInt8) { cc(17, value: mode) }

    /// Fast fwd / rew  CC18  MIDI value 0-127 (64 = centre)
    static let scrubPauseValue: UInt8 = 64
    /// +4 from centre — normal playback (TP-7 has no dedicated play CC)
    static let scrubPlayValue: UInt8 = 68

    func scrub(_ midiValue: UInt8) { cc(18, value: midiValue) }
    func scrubPlay()  { scrub(Self.scrubPlayValue) }
    func scrubPause() { scrub(Self.scrubPauseValue) }

    /// Mix mute  CC120  ch 1-6
    func mixMute(_ muted: Bool, channel: Int) {
        cc(120, value: muted ? 127 : 0, channel: UInt8(channel - 1))
    }

    // MARK: - TX-6 (incoming MIDI control — per Teenage Engineering TX-6 docs)

    private func tx6Ch(_ midiChannel1Based: Int) -> UInt8 {
        UInt8(clamping: midiChannel1Based - 1) & 0x0F
    }

    private func tx6Bool(_ on: Bool) -> UInt8 { on ? 127 : 0 }

    // Tracks 1–6
    func tx6TrackVolume(_ value: UInt8, track: Int)       { cc(7, value: value, channel: tx6Ch(track)) }
    func tx6TrackPan(_ value: UInt8, track: Int)          { cc(8, value: value, channel: tx6Ch(track)) }
    func tx6TrackGain(_ value: UInt8, track: Int)        { cc(9, value: value, channel: tx6Ch(track)) }
    func tx6SeqPattern(_ value: UInt8, track: Int)       { cc(14, value: value, channel: tx6Ch(track)) }
    func tx6TrackMuteSolo(_ on: Bool, track: Int)        { cc(120, value: tx6Bool(on), channel: tx6Ch(track)) }
    func tx6Filter(_ value: UInt8, track: Int)            { cc(74, value: value, channel: tx6Ch(track)) }
    func tx6EQHigh(_ value: UInt8, track: Int)           { cc(85, value: value, channel: tx6Ch(track)) }
    func tx6EQMid(_ value: UInt8, track: Int)            { cc(86, value: value, channel: tx6Ch(track)) }
    func tx6EQLow(_ value: UInt8, track: Int)             { cc(87, value: value, channel: tx6Ch(track)) }
    func tx6Compressor(_ value: UInt8, track: Int)      { cc(93, value: value, channel: tx6Ch(track)) }
    func tx6SynthWaveform(_ value: UInt8, track: Int)     { cc(3, value: value, channel: tx6Ch(track)) }
    func tx6SynthFrequency(_ value: UInt8, track: Int)   { cc(89, value: value, channel: tx6Ch(track)) }
    func tx6SynthLength(_ value: UInt8, track: Int)      { cc(90, value: value, channel: tx6Ch(track)) }
    func tx6SynthDetune(_ value: UInt8, track: Int)       { cc(95, value: value, channel: tx6Ch(track)) }
    func tx6FXISend(_ value: UInt8, track: Int)          { cc(91, value: value, channel: tx6Ch(track)) }
    func tx6AuxSend(_ value: UInt8, track: Int)          { cc(92, value: value, channel: tx6Ch(track)) }
    func tx6Aux2Send(_ value: UInt8, track: Int)         { cc(94, value: value, channel: tx6Ch(track)) }

    // Channel 7 (master / transport)
    func tx6MainVolume(_ value: UInt8)                    { cc(7, value: value, channel: tx6Ch(7)) }
    func tx6AuxVolume(_ value: UInt8)                     { cc(14, value: value, channel: tx6Ch(7)) }
    func tx6CueVolume(_ value: UInt8)                     { cc(15, value: value, channel: tx6Ch(7)) }
    func tx6LocalControl(_ on: Bool)                      { cc(122, value: tx6Bool(on), channel: tx6Ch(7)) }
    func tx6StartStopPulse()                              { cc(46, value: 127, channel: tx6Ch(7)) }
    /// Relative tempo: offset -64…+63 (0 = centre / no change from neutral).
    func tx6TempoRelative(offset: Int) {
        let v = (64 + offset).clamped(to: 0...127)
        cc(47, value: UInt8(v), channel: tx6Ch(7))
    }

    // FX I (MIDI channel 8) / FX II (channel 9)
    func tx6FXBusEnable(fx1: Bool, fx2: Bool) {
        cc(82, value: tx6Bool(fx1), channel: tx6Ch(8))
        cc(82, value: tx6Bool(fx2), channel: tx6Ch(9))
    }

    func tx6FXEngine(_ value: UInt8, fxSlot: Int) {
        let ch = fxSlot == 1 ? 8 : 9
        cc(15, value: value, channel: tx6Ch(ch))
    }

    func tx6FXParam1(_ value: UInt8, fxSlot: Int) { cc(12, value: value, channel: tx6Ch(fxSlot == 1 ? 8 : 9)) }
    func tx6FXParam2(_ value: UInt8, fxSlot: Int) { cc(13, value: value, channel: tx6Ch(fxSlot == 1 ? 8 : 9)) }
    func tx6FXParam3(_ value: UInt8, fxSlot: Int) { cc(14, value: value, channel: tx6Ch(fxSlot == 1 ? 8 : 9)) }

    func tx6FXIReturnLevel(_ value: UInt8)                { cc(7, value: value, channel: tx6Ch(8)) }
    func tx6FX2TrackSelect(_ value: UInt8)               { cc(9, value: value, channel: tx6Ch(9)) }
}

// MARK: - CBCentralManagerDelegate

extension BLEMIDIManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            connectionState = .disconnected
        case .poweredOff, .unauthorized, .unsupported:
            connectionState = .bluetoothOff
            midiChar = nil
            connectedDevice = nil
            discoveredDevices = []
            inferredDeviceProfile = nil
            deviceProfileOverride = nil
            advertisementLocalNames.removeAll()
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        if let local = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            advertisementLocalNames[peripheral.identifier] = local
        }
        guard !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) else { return }
        discoveredDevices.append(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedDevice = peripheral
        connectionState = .connected
        let displayName = peripheral.name
            ?? advertisementLocalNames[peripheral.identifier]
        inferredDeviceProfile = RemoteDeviceProfile.infer(fromName: displayName)
        if let name = displayName {
            KnownDevicesStore.record(name: name)
        }
        peripheral.delegate = self
        peripheral.discoverServices([Self.midiServiceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        connectedDevice = nil
        midiChar = nil
        connectionState = .disconnected
        inferredDeviceProfile = nil
        deviceProfileOverride = nil
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        connectionState = .disconnected
        inferredDeviceProfile = nil
    }
}

// MARK: - CBPeripheralDelegate

extension BLEMIDIManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        peripheral.services?
            .filter { $0.uuid == Self.midiServiceUUID }
            .forEach { peripheral.discoverCharacteristics([Self.midiCharUUID], for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        midiChar = service.characteristics?.first { $0.uuid == Self.midiCharUUID }
    }

    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        guard peripheral == connectedDevice else { return }
        let n = peripheral.name ?? advertisementLocalNames[peripheral.identifier]
        if let p = RemoteDeviceProfile.infer(fromName: n) {
            inferredDeviceProfile = p
        }
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
