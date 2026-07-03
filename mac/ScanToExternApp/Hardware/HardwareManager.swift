import Foundation
import Combine

/// HardwareManager coordinates BluetoothManager and USBSerialManager.
/// Single source of truth for last scan and overall connection state.
/// Preference: Bluetooth over USB when both available (per spec).
///
/// User-facing device discovery and pairing state lives in `DeviceRegistry`; this
/// class listens to the Devices view's connect/disconnect/forget requests and
/// routes them to the right underlying manager.
final class HardwareManager: ObservableObject {
    static let shared = HardwareManager()

    private let bluetooth = BluetoothManager()
    private let usb = USBSerialManager()

    /// Shared, UI-facing discovery + pairing state. Views observe this directly.
    let registry = DeviceRegistry.shared

    private var cancellables = Set<AnyCancellable>()
    private var notificationTokens: [NSObjectProtocol] = []

    @Published var lastScan: String?
    @Published var connectionState: ConnectionState = .disconnected
    @Published var activeSource: String = "none" // "bluetooth" | "usb" | "none"

    @Published var deviceName: String = ""
    @Published var batteryPercent: Int?

    let scanPublisher = PassthroughSubject<(text: String, source: String), Never>()

    private init() {
        setupBindings()
        setupDeviceRequestHandlers()
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

        // Battery updates from registry → menubar's batteryPercent
        registry.$battery
            .receive(on: RunLoop.main)
            .sink { [weak self] pct in
                self?.batteryPercent = pct
            }
            .store(in: &cancellables)
    }

    /// Bridge the DeviceRegistry's Notification-based UI actions into concrete calls
    /// on the right manager. The registry stays a pure state holder — it doesn't
    /// know about CoreBluetooth or serial ports.
    private func setupDeviceRequestHandlers() {
        let nc = NotificationCenter.default

        notificationTokens.append(nc.addObserver(forName: DeviceRegistry.connectRequest, object: nil, queue: .main) { [weak self] note in
            guard let self = self, let id = note.object as? String else { return }
            if let dev = self.registry.discovered.first(where: { $0.id == id }) {
                switch dev.kind {
                case .bluetooth: self.bluetooth.connect(to: id)
                case .usb:       self.usb.connect(to: id)
                }
            }
        })

        notificationTokens.append(nc.addObserver(forName: DeviceRegistry.disconnectRequest, object: nil, queue: .main) { [weak self] _ in
            self?.bluetooth.disconnect()
            self?.usb.stop()
            self?.usb.start() // keep USB polling alive after a manual disconnect
        })

        notificationTokens.append(nc.addObserver(forName: DeviceRegistry.forgetRequest, object: nil, queue: .main) { [weak self] _ in
            self?.registry.preferredDeviceID = nil
            self?.bluetooth.disconnect()
        })

        notificationTokens.append(nc.addObserver(forName: DeviceRegistry.refreshRequest, object: nil, queue: .main) { [weak self] _ in
            self?.forceRescan()
        })
    }

    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func handleNewScan(_ text: String, source: String) {
        lastScan = text
        activeSource = source
        // Live progress into the popover: text is fully reassembled at this point.
        ScanFlowState.shared.captured(text)
        scanPublisher.send((text: text, source: source))
        print("[Hardware] New scan from \(source): \(text.prefix(60))...")
    }

    private func handleConnectionStateChange(_ state: ConnectionState, source: String) {
        if source == "bluetooth" && state == .connected {
            activeSource = "bluetooth"
            connectionState = .connected
        } else if source == "usb" && state == .connected && activeSource != "bluetooth" {
            activeSource = "usb"
            connectionState = .connected
        } else if state == .disconnected {
            if source == activeSource {
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
