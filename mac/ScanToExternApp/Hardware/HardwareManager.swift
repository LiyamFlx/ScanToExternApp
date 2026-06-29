import Foundation
import Combine

/// HardwareManager coordinates BluetoothManager and USBSerialManager.
/// Single source of truth for last scan and overall connection state.
/// Preference: Bluetooth over USB when both available (per spec).
final class HardwareManager: ObservableObject {
    static let shared = HardwareManager()

    private let bluetooth = BluetoothManager()
    private let usb = USBSerialManager()

    private var cancellables = Set<AnyCancellable>()

    @Published var lastScan: String?
    @Published var connectionState: ConnectionState = .disconnected
    @Published var activeSource: String = "none" // "bluetooth" | "usb" | "none"

    @Published var deviceName: String = ""
    @Published var batteryPercent: Int?

    let scanPublisher = PassthroughSubject<(text: String, source: String), Never>()

    private init() {
        setupBindings()
        // Auto-start both managers (they handle their own discovery)
        bluetooth.startScanning()
        usb.start()
    }

    private func setupBindings() {
        // Bluetooth
        bluetooth.scanReceived
            .sink { [weak self] text in
                self?.handleNewScan(text, source: "bluetooth")
            }
            .store(in: &cancellables)

        bluetooth.connectionState
            .sink { [weak self] state in
                self?.handleConnectionStateChange(state, source: "bluetooth")
            }
            .store(in: &cancellables)

        bluetooth.deviceInfo
            .sink { [weak self] info in
                self?.deviceName = info.name
                self?.batteryPercent = info.battery
            }
            .store(in: &cancellables)

        bluetooth.$isConnected
            .sink { [weak self] connected in
                if connected {
                    self?.updateOverallState(prefer: "bluetooth")
                }
            }
            .store(in: &cancellables)

        // USB
        usb.scanReceived
            .sink { [weak self] text in
                self?.handleNewScan(text, source: "usb")
            }
            .store(in: &cancellables)

        usb.connectionState
            .sink { [weak self] state in
                self?.handleConnectionStateChange(state, source: "usb")
            }
            .store(in: &cancellables)

        usb.$isConnected
            .sink { [weak self] connected in
                if connected {
                    self?.updateOverallState(prefer: nil)
                }
            }
            .store(in: &cancellables)
    }

    private func handleNewScan(_ text: String, source: String) {
        // Always update lastScan
        lastScan = text
        activeSource = source

        // Emit to listeners (InjectionRouter, Preview, History, etc.)
        scanPublisher.send((text: text, source: source))

        // Update menu bar controller if available (via shared or notification for now)
        print("[Hardware] New scan from \(source): \(text.prefix(60))...")
    }

    private func handleConnectionStateChange(_ state: ConnectionState, source: String) {
        // Bluetooth preferred
        if source == "bluetooth" && state == .connected {
            activeSource = "bluetooth"
            connectionState = .connected
        } else if source == "usb" && state == .connected && activeSource != "bluetooth" {
            activeSource = "usb"
            connectionState = .connected
        } else if state == .disconnected {
            // Only downgrade if the active one disconnected
            if (source == activeSource) {
                if source == "bluetooth" && usb.isConnected {
                    activeSource = "usb"
                    connectionState = .connected
                } else if source == "usb" && bluetooth.isConnected {
                    activeSource = "bluetooth"
                    connectionState = .connected
                } else {
                    activeSource = "none"
                    connectionState = .disconnected
                }
            }
        }
    }

    private func updateOverallState(prefer: String?) {
        if (prefer == "bluetooth" || bluetooth.isConnected) && bluetooth.isConnected {
            activeSource = "bluetooth"
            connectionState = .connected
        } else if usb.isConnected {
            activeSource = "usb"
            connectionState = .connected
        } else {
            connectionState = .disconnected
            activeSource = "none"
        }
    }

    // Public helpers
    func disconnectAll() {
        bluetooth.disconnect()
        usb.stop()
        connectionState = .disconnected
        activeSource = "none"
    }

    func forceRescan() {
        bluetooth.startScanning()
        if !usb.isConnected {
            usb.start()
        }
    }

    /// Debug helper: simulate an incoming scan from hardware (for testing preview/injection/history without a physical device).
    func simulateScan(_ text: String = "The quick brown fox jumps over the lazy dog. This is a test scan from ScanToExternApp v5.0.") {
        print("[Hardware] DEBUG: Simulating scan: \(text.prefix(40))...")
        lastScan = text
        activeSource = "debug"
        connectionState = .connected
        scanPublisher.send((text: text, source: "debug"))
    }
}
