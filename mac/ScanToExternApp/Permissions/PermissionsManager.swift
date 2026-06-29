import AppKit
import Foundation
import ApplicationServices

class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published var hasAccessibility: Bool = false
    @Published var hasBluetooth: Bool = false

    private var pollTimer: Timer?

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

        // Poll for change, but stop after a bounded number of attempts so we never
        // leak a timer that runs forever if the user denies/ignores the prompt.
        pollTimer?.invalidate()
        var attempts = 0
        let maxAttempts = 60 // ~60 seconds
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            attempts += 1
            let trusted = AXIsProcessTrusted()
            self.hasAccessibility = trusted
            if trusted {
                timer.invalidate()
                self.pollTimer = nil
                print("Accessibility permission granted")
            } else if attempts >= maxAttempts {
                timer.invalidate()
                self.pollTimer = nil
                print("Accessibility permission not granted after \(maxAttempts)s — stopping poll")
            }
        }
    }

    var allCriticalPermissionsGranted: Bool {
        hasAccessibility
    }
}
