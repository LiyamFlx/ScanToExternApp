import AppKit
import Foundation

/// Fallback injector using NSPasteboard + synthetic Cmd+V.
/// Restores previous clipboard contents after a short delay.
/// Works universally but pollutes clipboard temporarily (hence fallback only).
final class ClipboardInjector {
    /// - Parameter targetApp: the app the paste should land in. We activate it first so
    ///   the synthetic Cmd+V is delivered to the right window (not our toast / menubar).
    func inject(_ text: String, targetApp: NSRunningApplication? = nil) {
        // Ensure the target app is frontmost before we paste.
        if let targetApp = targetApp, !targetApp.isTerminated, !targetApp.isActive {
            targetApp.activate(options: [])
            Thread.sleep(forTimeInterval: 0.12)
        }

        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Post Cmd+V (virtual key 0x09 is 'V')
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("[Clipboard] Failed to create CGEventSource")
            restoreClipboard(previousContent)
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
            self.restoreClipboard(previousContent)
        }

        print("[Clipboard] Injected via Cmd+V fallback into \(bundleID) (\(text.count) chars, restore in \(delay)s)")
    }

    private func restoreClipboard(_ previous: String?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let prev = previous {
            pasteboard.setString(prev, forType: .string)
        }
    }
}
