import Foundation
import CoreBluetooth
import Combine

/// BluetoothManager handles CoreBluetooth connection to Scanmarker devices using
/// Nordic UART Service (NUS). Discovery is always-on when Bluetooth is up so the
/// user can see nearby scanners in the Devices panel and pick one. The manager
/// only auto-connects when the user has already paired a specific device.
///
/// Reference: Scanmarker BLE Protocol in CLAUDE.md
final class BluetoothManager: NSObject, ObservableObject {
    // Nordic UART Service — Scanmarker uses this standard BLE profile
    private let nusServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let nusTXCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // scanner -> app
    private let nusRXCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // app -> scanner (rarely used)
    // Standard BLE Battery Service — read + notify for battery %
    private let batteryServiceUUID = CBUUID(string: "180F")
    private let batteryLevelCharUUID = CBUUID(string: "2A19")

    private var centralManager: CBCentralManager!
    /// All peripherals we've seen this session, keyed by identifier.uuidString.
    /// Kept so we can call `connect` on the exact CBPeripheral instance later —
    /// CoreBluetooth requires the same object, you can't rehydrate from just a UUID.
    private var knownPeripherals: [String: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?

    private var scanBuffer = ""
    private var silenceTimer: Timer?
    private var pruneTimer: Timer?

    // Publishers used by HardwareManager
    let scanReceived = PassthroughSubject<String, Never>()
    let connectionState = PassthroughSubject<ConnectionState, Never>()
    let deviceInfo = PassthroughSubject<(name: String, battery: Int?), Never>()

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var currentDeviceName: String = ""

    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        // Age out advertisements the user hasn't seen re-broadcast recently.
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            DeviceRegistry.shared.pruneStale()
        }
    }

    // MARK: - Public API (called from HardwareManager)

    /// Start (or continue) scanning for Scanmarker-like peripherals. Idempotent.
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("[BT] Central not powered on yet")
            return
        }
        // Idle if we have no paired preference, scanning while actively discovering.
        if DeviceRegistry.shared.preferredDeviceID == nil {
            DeviceRegistry.shared.setStatus(.scanning)
        }
        centralManager.scanForPeripherals(withServices: [nusServiceUUID],
                                          options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        print("[BT] Scanning for NUS peripherals")
    }

    func stopScanning() {
        centralManager.stopScan()
    }

    /// Attempt to connect to a specific peripheral by its identifier UUID string.
    /// Called from the Devices view when the user taps Connect.
    func connect(to peripheralID: String) {
        guard let target = knownPeripherals[peripheralID] else {
            print("[BT] connect(to:) — unknown peripheral \(peripheralID)")
            return
        }
        self.peripheral = target
        target.delegate = self
        centralManager.stopScan()
        DeviceRegistry.shared.setStatus(.connecting(target.name ?? "Scanmarker"))
        currentDeviceName = target.name ?? "Scanmarker"
        centralManager.connect(target, options: nil)
        // NOTE: we intentionally do NOT publish .connected here — that was the old
        // premature-connected bug. We wait for didConnect.
    }

    /// Disconnect from the current peripheral. Keeps the pairing preference so a
    /// later Connect (or app relaunch) reconnects to the same device.
    func disconnect() {
        if let p = peripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        peripheral = nil
        txCharacteristic = nil
        isConnected = false
        connectionState.send(.disconnected)
        DeviceRegistry.shared.setStatus(centralManager.state == .poweredOn ? .idle : .bluetoothOff)
        DeviceRegistry.shared.setBattery(nil)
    }

    // MARK: - Incoming data

    private func handleIncomingData(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        scanBuffer += chunk

        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.32, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let complete = self.scanBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !complete.isEmpty {
                print("[BT] Complete scan reassembled (\(complete.count) chars)")
                self.scanReceived.send(complete)
            }
            self.scanBuffer = ""
        }
    }

    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            print("[BT] Max reconnect attempts reached")
            DeviceRegistry.shared.setStatus(.failed("Couldn't reach the scanner. Move it closer or re-pair from the Devices panel."))
            return
        }
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0)
        print("[BT] Scheduling reconnect attempt #\(reconnectAttempts) in \(delay)s")
        if let name = peripheral?.name ?? knownPeripherals[DeviceRegistry.shared.preferredDeviceID ?? ""]?.name {
            DeviceRegistry.shared.setStatus(.reconnecting(name))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.startScanning()
        }
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("[BT] Bluetooth powered on")
            DeviceRegistry.shared.setStatus(DeviceRegistry.shared.preferredDeviceID == nil ? .scanning : .scanning)
            startScanning()
        case .poweredOff:
            connectionState.send(.disconnected)
            DeviceRegistry.shared.setStatus(.bluetoothOff)
            print("[BT] Bluetooth powered off")
        case .unauthorized:
            DeviceRegistry.shared.setStatus(.bluetoothUnauthorized)
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Unknown BLE device"
        let idString = peripheral.identifier.uuidString

        // Remember the CBPeripheral instance so a later connect(to:) can dispatch to it.
        knownPeripherals[idString] = peripheral

        // Publish into the registry so the Devices panel updates live.
        DeviceRegistry.shared.upsert(.init(
            id: idString,
            name: name,
            kind: .bluetooth,
            rssi: RSSI.intValue,
            lastSeen: Date()
        ))

        // Auto-connect only if this is the paired device. Otherwise we stay in scan mode
        // and let the user choose from the Devices panel.
        if DeviceRegistry.shared.preferredDeviceID == idString, self.peripheral == nil {
            print("[BT] Found paired device \(name); auto-connecting")
            connect(to: idString)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[BT] Connected to \(peripheral.name ?? "device")")
        reconnectAttempts = 0
        isConnected = true
        currentDeviceName = peripheral.name ?? "Scanmarker"
        connectionState.send(.connected)
        deviceInfo.send((name: currentDeviceName, battery: nil))
        DeviceRegistry.shared.setStatus(.connected(currentDeviceName, .bluetooth))
        // Persist pairing so next launch auto-connects.
        DeviceRegistry.shared.preferredDeviceID = peripheral.identifier.uuidString

        // Discover both NUS (data) and the standard Battery Service (0x180F).
        peripheral.discoverServices([nusServiceUUID, batteryServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[BT] Failed to connect: \(error?.localizedDescription ?? "unknown")")
        DeviceRegistry.shared.setStatus(.failed(error?.localizedDescription ?? "Connection failed"))
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[BT] Disconnected: \(error?.localizedDescription ?? "no error")")
        isConnected = false
        connectionState.send(.disconnected)
        DeviceRegistry.shared.setBattery(nil)
        self.peripheral = nil
        self.txCharacteristic = nil
        // Only backoff-reconnect if the user still wants this device paired.
        if DeviceRegistry.shared.preferredDeviceID == peripheral.identifier.uuidString {
            scheduleReconnect()
        } else {
            DeviceRegistry.shared.setStatus(.idle)
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == nusServiceUUID {
                peripheral.discoverCharacteristics([nusTXCharacteristicUUID, nusRXCharacteristicUUID], for: service)
            } else if service.uuid == batteryServiceUUID {
                peripheral.discoverCharacteristics([batteryLevelCharUUID], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == nusTXCharacteristicUUID {
                txCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("[BT] Subscribed to NUS TX for incoming OCR text")
            } else if characteristic.uuid == batteryLevelCharUUID {
                // Read once immediately, then subscribe for updates.
                peripheral.readValue(for: characteristic)
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == nusTXCharacteristicUUID, let data = characteristic.value {
            handleIncomingData(data)
        } else if characteristic.uuid == batteryLevelCharUUID, let data = characteristic.value, let first = data.first {
            let pct = Int(first)
            print("[BT] Battery: \(pct)%")
            DeviceRegistry.shared.setBattery(pct)
            deviceInfo.send((name: currentDeviceName, battery: pct))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        peripheral.discoverServices([nusServiceUUID, batteryServiceUUID])
    }
}
