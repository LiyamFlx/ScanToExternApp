import AppKit
import Foundation

/// Central router for all injection paths.
/// - Always broadcasts scans to the browser extension via WS (for web apps like Google Docs, Gmail, etc.)
/// - For non-browser native apps: tries AXInjector first, falls back to ClipboardInjector.
final class InjectionRouter {
    static let shared = InjectionRouter()

    private let ax = AXInjector()
    private let clipboard = ClipboardInjector()
    private let bridge = WebSocketBridge()

    private var lastBroadcastId: String?

    private init() {
        bridge.start()
    }

    deinit {
        bridge.stop()
    }

    /// - Parameter target: the app that was focused when the scan arrived (captured BEFORE
    ///   our preview window stole focus). We re-activate it so injection lands in the right place.
    func route(_ text: String, target: NSRunningApplication? = nil) {
        // Defensive: an empty/whitespace scan would just steal focus + paste nothing.
        // Hardware silence timers already filter this, but the path is reachable from
        // simulateScan/URL-scheme/re-inject too.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("[Router] Skipping empty scan")
            return
        }

        let id = UUID().uuidString
        lastBroadcastId = id

        let frontApp = target ?? NSWorkspace.shared.frontmostApplication
        let frontAppBundleID = frontApp?.bundleIdentifier ?? ""
        let targetLabel = frontApp?.localizedName ?? frontAppBundleID.components(separatedBy: ".").last ?? "focused app"

        let browserBundleIDs: Set<String> = [
            "com.google.Chrome",
            "com.apple.Safari",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.operasoftware.Opera"
        ]
        let isBrowser = browserBundleIDs.contains(frontAppBundleID)

        // Announce that we're about to inject — the popover's "Step 3" section binds to this.
        ScanFlowState.shared.injecting(into: isBrowser ? "\(targetLabel) (browser)" : targetLabel)

        // All activation + injection happens off the main thread so we never block the UI
        // with the activation settle delay (Thread.sleep). The actual AX/clipboard calls are
        // thread-safe to invoke from a background queue.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 1. Re-activate the original target app so it (not our toast) is frontmost.
            if let target = target, !target.isTerminated, !target.isActive {
                target.activate(options: [])
                Thread.sleep(forTimeInterval: 0.2) // let activation settle
            }

            // 2. Broadcast to the browser extension AFTER the target is frontmost, so the
            //    extension's active-tab logic targets the right window.
            self.bridge.broadcastScan(text: text, id: id)

            // 3. Native injection (skipped for browsers — the extension handles the DOM).
            if isBrowser {
                print("[Router] Browser frontmost (\(frontAppBundleID)) — extension handles DOM injection")
                ScanFlowState.shared.injected(text.count, into: "\(targetLabel) (via browser extension)")
                return
            }

            let targetPID = target?.processIdentifier
            let method = SettingsStore.shared.injectionMethod
            if method == "clipboard" {
                self.clipboard.inject(text, targetApp: target)
                print("[Router] Forced clipboard injection (per settings) into \(frontAppBundleID)")
                ScanFlowState.shared.injected(text.count, into: "\(targetLabel) (clipboard)")
            } else if self.ax.inject(text, targetPID: targetPID) {
                print("[Router] Injected via AXUIElement into \(frontAppBundleID)")
                ScanFlowState.shared.injected(text.count, into: targetLabel)
            } else {
                self.clipboard.inject(text, targetApp: target)
                print("[Router] AX failed — injected via clipboard fallback into \(frontAppBundleID)")
                ScanFlowState.shared.injected(text.count, into: "\(targetLabel) (clipboard fallback)")
            }
        }
        // Note: history is recorded by the caller after preview / AI processing.
    }

    /// For manual re-inject from history etc. Uses current frontmost app as target.
    func reInject(_ text: String) {
        route(text, target: nil)
    }

    /// Test-only: broadcast a scan to WebSocket clients without any preview/injection.
    /// Used by the SCANAPP_WSTEST verification hook to confirm frame delivery.
    func testBroadcast(_ text: String) {
        bridge.broadcastScan(text: text, id: UUID().uuidString)
    }

    func requestAXPermissionIfNeeded() {
        if !ax.isTrusted {
            ax.requestAccessibilityPermission()
        }
    }
}
