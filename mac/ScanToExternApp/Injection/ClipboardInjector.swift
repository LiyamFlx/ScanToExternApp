import AppKit
import Foundation

/// Fallback injector using NSPasteboard + synthetic Cmd+V.
/// Restores previous clipboard contents after a short delay.
/// Works universally but pollutes clipboard temporarily (hence fallback only).
final class ClipboardInjector {
    func inject(_ text: String) {
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

        // Restore original clipboard after delay (gives time for paste to register)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.restoreClipboard(previousContent)
        }

        print("[Clipboard] Injected via Cmd+V fallback (\(text.count) chars)")
    }

    private func restoreClipboard(_ previous: String?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let prev = previous {
            pasteboard.setString(prev, forType: .string)
        }
    }
}
