import AppKit
import Foundation

/// Fallback injector using NSPasteboard + synthetic Cmd+V.
/// Restores previous clipboard contents after a short delay.
/// Works universally but pollutes clipboard temporarily (hence fallback only).
final class ClipboardInjector {
    /// Monotonic counter — only the injection holding the latest generation at restore-time
    /// is allowed to restore. Prevents two rapid scans (realistic for a scan pen used
    /// continuously) from racing: without this, scan B's restore fires after scan A's and
    /// clobbers the correctly-restored original back to scan A's leftover text.
    private static var generation: Int = 0
    private static var savedClipboard: String??  // outer optional = "not yet captured this burst"
    private static let stateQueue = DispatchQueue(label: "com.topscan.ScanToExternApp.clipboardInjector")

    /// - Parameter targetApp: the app the paste should land in. We activate it first so
    ///   the synthetic Cmd+V is delivered to the right window (not our toast / menubar).
    func inject(_ text: String, targetApp: NSRunningApplication? = nil) {
        // Ensure the target app is frontmost before we paste.
        if let targetApp = targetApp, !targetApp.isTerminated, !targetApp.isActive {
            targetApp.activate(options: [])
            Thread.sleep(forTimeInterval: 0.12)
        }

        let myGen: Int = Self.stateQueue.sync {
            Self.generation += 1
            if Self.savedClipboard == nil {
                Self.savedClipboard = .some(NSPasteboard.general.string(forType: .string))
            }
            return Self.generation
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Post Cmd+V (virtual key 0x09 is 'V')
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("[Clipboard] Failed to create CGEventSource")
            restoreIfLatest(myGen)
            return
        }

        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)

        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand

        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)

        // Restore original clipboard after a delay. Browsers/Electron read the pasteboard
        // asynchronously via their JS event loop, so we use a generous delay to avoid
        // clearing the clipboard before the paste has actually consumed it.
        let bundleID = (targetApp ?? NSWorkspace.shared.frontmostApplication)?.bundleIdentifier ?? ""
        let isSlowPaster = ["chrome", "safari", "firefox", "edge", "electron", "slack", "code"]
            .contains { bundleID.lowercased().contains($0) }
        let delay: TimeInterval = isSlowPaster ? 0.7 : 0.45

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.restoreIfLatest(myGen)
        }

        print("[Clipboard] Injected via Cmd+V fallback into \(bundleID) (\(text.count) chars, restore in \(delay)s)")
    }

    /// Only restores if no newer injection has started since this one began — otherwise the
    /// newer injection owns the eventual restore, and firing anyway would overwrite its write
    /// with this (now stale) capture of the "original" clipboard.
    private func restoreIfLatest(_ myGen: Int) {
        Self.stateQueue.sync {
            guard Self.generation == myGen else {
                print("[Clipboard] Newer injection superseded this restore, skipping")
                return
            }
            let previous = Self.savedClipboard.flatMap { $0 }
            Self.savedClipboard = nil
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if let prev = previous {
                pasteboard.setString(prev, forType: .string)
            }
        }
    }
}
