import Foundation
import ORSSerial
import Combine

/// USBSerialManager wraps ORSSerialPort for Scanmarker USB (Silicon Labs VCP).
/// Baud: 115200, 8N1. Same text protocol as BLE: UTF-8 chunks reassembled on silence.
final class USBSerialManager: NSObject, ObservableObject {
    let scanReceived = PassthroughSubject<String, Never>()
    let connectionState = PassthroughSubject<ConnectionState, Never>()

    private var serialPort: ORSSerialPort?
    private var scanBuffer = ""
    private var lastDataTime = Date.distantPast
    private var silenceTimer: Timer?

    @Published var isConnected: Bool = false
    @Published var currentDevicePath: String = ""

    private let baudRate: UInt = 115200
    private let possibleDeviceNames = ["SLAB_USBtoUART", "cu.SLAB", "tty.SLAB", "Scanmarker"] // common VCP names

    func start() {
        if let port = findScanmarkerPort() {
            openPort(port)
        } else {
            print("[USB] No Scanmarker VCP found. Will poll...")
            // Simple poll every 3s for hotplug
            Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] timer in
                if let self = self, !self.isConnected {
                    if let p = self.findScanmarkerPort() {
                        timer.invalidate()
                        self.openPort(p)
                    }
                }
            }
        }
    }

    func stop() {
        serialPort?.close()
        serialPort = nil
        isConnected = false
        connectionState.send(.disconnected)
    }

    private func findScanmarkerPort() -> ORSSerialPort? {
        let available = ORSSerialPortManager.shared().availablePorts
        for port in available {
            let path = port.path.lowercased()
            let name = port.name.lowercased()
            if possibleDeviceNames.contains(where: { path.contains($0.lowercased()) || name.contains($0.lowercased()) }) {
                print("[USB] Found candidate VCP port: \(port.path) (\(port.name))")
                return port
            }
        }
        return nil
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
        // open() is void; success/failure notified via delegate or isOpen
        if port.isOpen {
            serialPort = port
            isConnected = true
            currentDevicePath = port.path
            connectionState.send(.connected)
            print("[USB] Opened \(port.path) @ \(baudRate) 8N1")
        } else {
            print("[USB] Failed to open \(port.path) (will rely on delegate)")
            // The delegate serialPortWasOpened or error will fire
        }
    }

    private func handleData(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        scanBuffer += chunk
        lastDataTime = Date()

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
        // Attempt re-start scan
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.start()
        }
    }

    func serialPort(_ serialPort: ORSSerialPort, didEncounterError error: Error) {
        print("[USB] Serial error: \(error)")
        isConnected = false
        connectionState.send(.disconnected)
    }
}
