import AppKit
import Foundation
import ApplicationServices

class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published var hasAccessibility: Bool = false
    @Published var hasBluetooth: Bool = false

    private init() {}

    func checkAll() {
        hasAccessibility = AXIsProcessTrusted()
        // Bluetooth permission is requested implicitly via CBCentralManager usage
        // hasBluetooth will be updated from CBCentralManager state in BluetoothManager
        print("Permissions check - Accessibility: \(hasAccessibility)")
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)

        // Poll for change
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            let trusted = AXIsProcessTrusted()
            self.hasAccessibility = trusted
            if trusted {
                timer.invalidate()
                print("Accessibility permission granted")
            }
        }
    }
}
