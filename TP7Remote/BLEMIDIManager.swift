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

    private var central: CBCentralManager!
    private var midiChar: CBCharacteristic?

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

    /// Fast fwd / rew  CC18  MIDI value 0-127 (64 = stopped)
    func scrub(_ midiValue: UInt8) { cc(18, value: midiValue) }

    /// Mix mute  CC120  ch 1-6
    func mixMute(_ muted: Bool, channel: Int) {
        cc(120, value: muted ? 127 : 0, channel: UInt8(channel - 1))
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEMIDIManager: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            connectionState = .disconnected
        case .poweredOff, .unauthorized, .unsupported:
            connectionState = .bluetoothOff
            midiChar = nil
            connectedDevice = nil
            discoveredDevices = []
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard !discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) else { return }
        discoveredDevices.append(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedDevice = peripheral
        connectionState = .connected
        peripheral.delegate = self
        peripheral.discoverServices([Self.midiServiceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        connectedDevice = nil
        midiChar = nil
        connectionState = .disconnected
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        connectionState = .disconnected
    }
}

// MARK: - CBPeripheralDelegate

extension BLEMIDIManager: @preconcurrency CBPeripheralDelegate {
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
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
