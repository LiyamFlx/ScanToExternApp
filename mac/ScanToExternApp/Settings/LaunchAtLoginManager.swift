import Foundation
import ServiceManagement

/// macOS 13+ launch at login using SMAppService (recommended, no deprecated SMLoginItem).
enum LaunchAtLoginManager {
    static func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp

        do {
            if enabled {
                try service.register()
                print("[LaunchAtLogin] Registered for launch at login")
            } else {
                try service.unregister()
                print("[LaunchAtLogin] Unregistered from launch at login")
            }
        } catch {
            print("[LaunchAtLogin] Failed to \(enabled ? "register" : "unregister"): \(error)")
        }
    }

    static func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Call once at app launch to ensure the setting matches reality (user may have toggled in System Settings).
    static func syncWithSetting() {
        let desired = SettingsStore.shared.launchAtLogin
        let current = isEnabled()

        if desired && !current {
            setEnabled(true)
        } else if !desired && current {
            setEnabled(false)
        }
    }
}
