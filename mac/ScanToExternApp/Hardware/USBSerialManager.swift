import Foundation
import ORSSerial
import Combine

/// USBSerialManager wraps ORSSerialPort for Scanmarker USB (Silicon Labs VCP).
/// Baud: 115200, 8N1. Same text protocol as BLE: UTF-8 chunks reassembled on silence.
///
/// Auto-connects on plug-in — physically inserting the cable is enough consent, no
/// separate pair step is needed. Publishes the port into `DeviceRegistry` so it
/// appears alongside BLE devices in the Devices panel.
final class USBSerialManager: NSObject, ObservableObject {
    let scanReceived = PassthroughSubject<String, Never>()
    let connectionState = PassthroughSubject<ConnectionState, Never>()

    private var serialPort: ORSSerialPort?
    private var scanBuffer = ""
    private var silenceTimer: Timer?
    private var pollTimer: Timer?

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var currentDevicePath: String = ""

    private let baudRate: UInt = 115200
    private let possibleDeviceNames = ["SLAB_USBtoUART", "cu.SLAB", "tty.SLAB", "Scanmarker"]

    func start() {
        pollAndPublish() // seed the Devices panel immediately
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.pollAndPublish()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        serialPort?.close()
        serialPort = nil
        isConnected = false
        connectionState.send(.disconnected)
    }

    /// Reflect the currently attached candidate ports into DeviceRegistry, and open
    /// one automatically if we don't already have an open port.
    private func pollAndPublish() {
        let available = ORSSerialPortManager.shared().availablePorts
        var candidates: [ORSSerialPort] = []
        for port in available {
            let path = port.path.lowercased()
            let name = port.name.lowercased()
            if possibleDeviceNames.contains(where: { path.contains($0.lowercased()) || name.contains($0.lowercased()) }) {
                candidates.append(port)
                DeviceRegistry.shared.upsert(.init(
                    id: port.path,
                    name: "\(port.name) (USB)",
                    kind: .usb,
                    rssi: nil,
                    lastSeen: Date()
                ))
            }
        }

        // Age out USB rows we no longer see (unplugged).
        let seenPaths = Set(candidates.map { $0.path })
        for row in DeviceRegistry.shared.discovered where row.kind == .usb && !seenPaths.contains(row.id) {
            DeviceRegistry.shared.remove(id: row.id)
        }

        // Auto-open the first candidate if nothing's open.
        if !isConnected, let first = candidates.first {
            openPort(first)
        }
    }

    func connect(to path: String) {
        guard let port = ORSSerialPortManager.shared().availablePorts.first(where: { $0.path == path }) else {
            print("[USB] connect(to:) — no port at \(path)")
            return
        }
        openPort(port)
    }

    private func openPort(_ port: ORSSerialPort) {
        port.baudRate = NSNumber(value: baudRate)
        port.parity = .none
        port.numberOfStopBits = 1
        port.numberOfDataBits = 8
        port.usesRTSCTSFlowControl = false
        port.usesDTRDSRFlowControl = false
        port.usesDCDOutputFlowControl = false
        port.delegate = self

        port.open()
        if port.isOpen {
            serialPort = port
            isConnected = true
            currentDevicePath = port.path
            connectionState.send(.connected)
            DeviceRegistry.shared.setStatus(.connected(port.name, .usb))
            print("[USB] Opened \(port.path) @ \(baudRate) 8N1")
        } else {
            print("[USB] Failed to open \(port.path) (will rely on delegate)")
        }
    }

    private func handleData(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        scanBuffer += chunk

        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.32, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            let complete = self.scanBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !complete.isEmpty {
                print("[USB] Complete scan reassembled (\(complete.count) chars)")
                self.scanReceived.send(complete)
            }
            self.scanBuffer = ""
        }
    }
}

extension USBSerialManager: ORSSerialPortDelegate {
    func serialPortWasOpened(_ serialPort: ORSSerialPort) {
        print("[USB] Delegate: port opened successfully")
        if !isConnected {
            self.serialPort = serialPort
            isConnected = true
            currentDevicePath = serialPort.path
            connectionState.send(.connected)
            DeviceRegistry.shared.setStatus(.connected(serialPort.name, .usb))
        }
    }

    func serialPort(_ serialPort: ORSSerialPort, didReceive data: Data) {
        handleData(data)
    }

    func serialPortWasRemovedFromSystem(_ serialPort: ORSSerialPort) {
        print("[USB] Port removed from system")
        self.serialPort = nil
        isConnected = false
        connectionState.send(.disconnected)
        DeviceRegistry.shared.remove(id: serialPort.path)
        // Poll timer keeps running; next tick will pick it up if reattached.
    }

    func serialPort(_ serialPort: ORSSerialPort, didEncounterError error: Error) {
        print("[USB] Serial error: \(error)")
        isConnected = false
        connectionState.send(.disconnected)
        DeviceRegistry.shared.setStatus(.failed(error.localizedDescription))
    }
}
