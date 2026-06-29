import Foundation
import CoreBluetooth
import Combine

/// BluetoothManager handles CoreBluetooth connection to Scanmarker devices using Nordic UART Service (NUS).
/// Reference: Scanmarker BLE Protocol in CLAUDE.md
final class BluetoothManager: NSObject, ObservableObject {
    // NUS UUIDs
    private let nusServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let nusTXCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // scanner -> app (RX for us)
    private let nusRXCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // app -> scanner (rarely used)

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?

    private var scanBuffer = ""
    private var lastDataTime = Date.distantPast
    private var silenceTimer: Timer?

    // Public publishers (used by HardwareManager)
    let scanReceived = PassthroughSubject<String, Never>()
    let connectionState = PassthroughSubject<ConnectionState, Never>()
    let deviceInfo = PassthroughSubject<(name: String, battery: Int?), Never>()

    @Published var isConnected: Bool = false
    @Published var currentDeviceName: String = ""

    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("[BT] Central not powered on yet")
            return
        }
        connectionState.send(.disconnected)
        print("[BT] Starting scan for Scanmarker NUS service: \(nusServiceUUID)")
        centralManager.scanForPeripherals(withServices: [nusServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScanning() {
        centralManager.stopScan()
    }

    func disconnect() {
        if let p = peripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        peripheral = nil
        txCharacteristic = nil
        isConnected = false
        connectionState.send(.disconnected)
    }

    private func connect(to peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
        connectionState.send(.connected)
    }

    private func handleIncomingData(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }

        scanBuffer += chunk
        lastDataTime = Date()

        // Cancel previous silence timer
        silenceTimer?.invalidate()

        // Schedule emission after ~300ms of silence
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
            return
        }
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0) // exponential backoff capped at 30s
        print("[BT] Scheduling reconnect attempt #\(reconnectAttempts) in \(delay)s")
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
            startScanning()
        case .poweredOff:
            connectionState.send(.disconnected)
            print("[BT] Bluetooth powered off")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown Scanmarker"
        print("[BT] Discovered: \(name) RSSI:\(RSSI)")

        // Prefer devices with Scanmarker in name or that have the service
        if name.lowercased().contains("scanmarker") || (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.contains(nusServiceUUID) == true {
            connect(to: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("[BT] Connected to \(peripheral.name ?? "device")")
        reconnectAttempts = 0
        isConnected = true
        currentDeviceName = peripheral.name ?? "Scanmarker"
        connectionState.send(.connected)
        deviceInfo.send((name: currentDeviceName, battery: nil))

        // Discover services
        peripheral.discoverServices([nusServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[BT] Failed to connect: \(error?.localizedDescription ?? "unknown")")
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("[BT] Disconnected: \(error?.localizedDescription ?? "no error")")
        isConnected = false
        connectionState.send(.disconnected)
        self.peripheral = nil
        self.txCharacteristic = nil
        scheduleReconnect()
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == nusServiceUUID {
            peripheral.discoverCharacteristics([nusTXCharacteristicUUID, nusRXCharacteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == nusTXCharacteristicUUID {
                txCharacteristic = characteristic
                // Subscribe to notifications (scanner pushes data here)
                peripheral.setNotifyValue(true, for: characteristic)
                print("[BT] Subscribed to TX characteristic for incoming OCR text")
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == nusTXCharacteristicUUID, let data = characteristic.value else { return }
        handleIncomingData(data)
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        // Re-discover if needed
        peripheral.discoverServices([nusServiceUUID])
    }
}
