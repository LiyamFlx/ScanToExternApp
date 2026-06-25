import AppKit
import ApplicationServices
import Foundation

/// Primary text injector using macOS Accessibility (AXUIElement) API.
/// Direct insertion into focused native text fields (TextEdit, Notes, Word, Mail, etc).
/// Returns true on success; caller should fallback to ClipboardInjector on false.
final class AXInjector {
    func inject(_ text: String) -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            print("[AX] No frontmost app")
            return false
        }

        let pid = frontmostApp.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        var focusedElementRef: AnyObject?
        let copyResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElementRef)
        guard copyResult == .success, let focusedElement = focusedElementRef else {
            print("[AX] No focused UI element")
            return false
        }

        let element = focusedElement as! AXUIElement

        // Check if the element supports setting selected text (most text fields do)
        var settable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        if settableResult != .success || !settable.boolValue {
            // Some elements only support value attribute
            var valueSettable: DarwinBoolean = false
            AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &valueSettable)
            if !valueSettable.boolValue {
                print("[AX] Focused element does not support setting text")
                return false
            }
            // Fallback path: set full value (overwrites)
            AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
            return true
        }

        // Preferred: set selected text (inserts at cursor or replaces selection)
        let setResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        if setResult == .success {
            return true
        }

        print("[AX] AXUIElementSetAttributeValue failed: \(setResult.rawValue)")
        return false
    }

    /// Triggers the system Accessibility permission prompt if not already trusted.
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Synchronous trusted check (no prompt).
    var isTrusted: Bool {
        return AXIsProcessTrusted()
    }
}
