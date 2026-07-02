import Foundation
import Combine

/// Shared, UI-facing state for hardware discovery, pairing, and live connection.
/// Owned by `HardwareManager`; observed by SwiftUI views.
///
/// This is the single source of truth for what the Devices panel shows:
/// - which peripherals are currently advertising / plugged in,
/// - which one (if any) the user has paired with,
/// - the current phase of the link (scanning, connecting, connected, reconnecting, failed),
/// - live battery / RSSI for the paired device.
///
/// `preferredDeviceID` persists across launches in UserDefaults so a paired
/// Scanmarker auto-reconnects silently on next start; if unset, the app stays
/// in `.scanning` until the user picks something from the Devices panel.
final class DeviceRegistry: ObservableObject {
    static let shared = DeviceRegistry()

    enum Kind: String { case bluetooth, usb }

    struct Device: Identifiable, Equatable {
        let id: String            // BT: peripheral.identifier.uuidString  /  USB: port path
        let name: String
        let kind: Kind
        var rssi: Int?            // BT only; nil for USB
        var lastSeen: Date        // last advertisement / poll hit — used to age out
    }

    /// Coarse link status, granular enough that the UI can distinguish
    /// "still looking" from "actively trying to connect to X" from "connected".
    enum Status: Equatable {
        case bluetoothOff
        case bluetoothUnauthorized
        case idle                             // BT on, no paired device, not scanning
        case scanning                         // BT on, actively scanning
        case connecting(String)               // trying to establish a link to <name>
        case connected(String, Kind)          // link up to <name> via <kind>
        case reconnecting(String)             // paired device dropped, backing off
        case failed(String)                   // human-readable reason; the UI can surface this
    }

    @Published var discovered: [Device] = []
    @Published var status: Status = .idle
    @Published var battery: Int?              // paired-device battery %; nil until read

    /// Persisted ID (BT peripheral UUID string or USB port path) of the user-selected device.
    /// nil = no preference; on next launch the app just shows discovery UI.
    @Published var preferredDeviceID: String? {
        didSet {
            UserDefaults.standard.set(preferredDeviceID, forKey: Self.preferredKey)
        }
    }

    private static let preferredKey = "preferredDeviceID"

    private init() {
        self.preferredDeviceID = UserDefaults.standard.string(forKey: Self.preferredKey)
    }

    // MARK: - Called by BluetoothManager / USBSerialManager

    /// Upsert a device into the discovered list. Called every time an advertisement or a USB
    /// poll hit arrives. Preserves last-known RSSI when the new sample doesn't include it.
    func upsert(_ device: Device) {
        DispatchQueue.main.async {
            if let idx = self.discovered.firstIndex(where: { $0.id == device.id }) {
                var updated = device
                if updated.rssi == nil { updated.rssi = self.discovered[idx].rssi }
                self.discovered[idx] = updated
            } else {
                self.discovered.append(device)
            }
        }
    }

    /// Drop a device from the list (e.g. USB unplugged, BT advertisement gone stale).
    func remove(id: String) {
        DispatchQueue.main.async {
            self.discovered.removeAll { $0.id == id }
        }
    }

    /// Age out BT rows that haven't been re-advertised recently.
    /// USB rows are exempt — their presence is a live poll, not a stale ad.
    func pruneStale(olderThan seconds: TimeInterval = 20) {
        DispatchQueue.main.async {
            let cutoff = Date().addingTimeInterval(-seconds)
            self.discovered.removeAll { $0.kind == .bluetooth && $0.lastSeen < cutoff && $0.id != self.preferredDeviceID }
        }
    }

    func setStatus(_ s: Status) {
        DispatchQueue.main.async { self.status = s }
    }

    func setBattery(_ pct: Int?) {
        DispatchQueue.main.async { self.battery = pct }
    }

    // MARK: - UI actions (view calls these; HardwareManager listens)

    /// The Devices view emits these via `NotificationCenter`. HardwareManager subscribes and
    /// routes to the right underlying manager. Keeps the registry a pure state holder — it
    /// doesn't know about CoreBluetooth or serial ports.
    static let connectRequest = Notification.Name("scanapp.device.connect")
    static let disconnectRequest = Notification.Name("scanapp.device.disconnect")
    static let forgetRequest = Notification.Name("scanapp.device.forget")
    static let refreshRequest = Notification.Name("scanapp.device.refresh")

    func requestConnect(to id: String) {
        NotificationCenter.default.post(name: Self.connectRequest, object: id)
    }
    func requestDisconnect() {
        NotificationCenter.default.post(name: Self.disconnectRequest, object: nil)
    }
    func requestForget() {
        NotificationCenter.default.post(name: Self.forgetRequest, object: nil)
    }
    func requestRefresh() {
        NotificationCenter.default.post(name: Self.refreshRequest, object: nil)
    }
}
