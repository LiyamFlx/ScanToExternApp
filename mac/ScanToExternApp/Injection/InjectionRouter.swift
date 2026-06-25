import AppKit
import Foundation

/// Central router for all injection paths.
/// - Always broadcasts scans to the browser extension via WS (for web apps like Google Docs, Gmail, etc.)
/// - For non-browser native apps: tries AXInjector first, falls back to ClipboardInjector.
final class InjectionRouter {
    private let ax = AXInjector()
    private let clipboard = ClipboardInjector()
    private let bridge = WebSocketBridge()

    private var lastBroadcastId: String?

    init() {
        bridge.start()
    }

    deinit {
        bridge.stop()
    }

    func route(_ text: String) {
        let id = UUID().uuidString
        lastBroadcastId = id

        // 1. Always send to browser extension (web content scripts handle Google Docs, etc.)
        bridge.broadcastScan(text: text, id: id)

        // 2. For native desktop apps, attempt direct AX injection
        let frontAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""

        let browserBundleIDs: Set<String> = [
            "com.google.Chrome",
            "com.apple.Safari",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.operasoftware.Opera"
        ]

        if !browserBundleIDs.contains(frontAppBundleID) {
            if ax.inject(text) {
                print("[Router] Injected via AXUIElement into \(frontAppBundleID)")
            } else {
                clipboard.inject(text)
                print("[Router] AX failed — injected via clipboard fallback into \(frontAppBundleID)")
            }
        } else {
            print("[Router] Browser frontmost (\(frontAppBundleID)) — extension will handle DOM injection")
        }

        // 3. Record in history is handled by caller (after preview / AI processing)
    }

    /// For manual re-inject from history etc.
    func reInject(_ text: String) {
        route(text)
    }

    func requestAXPermissionIfNeeded() {
        if !ax.isTrusted {
            ax.requestAccessibilityPermission()
        }
    }
}
