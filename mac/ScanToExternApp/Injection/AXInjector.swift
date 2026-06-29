import AppKit
import ApplicationServices
import Foundation

/// Primary text injector using macOS Accessibility (AXUIElement) API.
/// Direct insertion into focused native text fields (TextEdit, Notes, Word, Mail, etc).
/// Returns true on success; caller should fallback to ClipboardInjector on false.
final class AXInjector {
    /// Injects into a specific target app (by PID). If `pid` is nil, falls back to the
    /// current frontmost app. The target PID matters because by the time the user clicks
    /// "Inject" in our preview toast, OUR window is frontmost — not the app they were typing in.
    func inject(_ text: String, targetPID: pid_t? = nil) -> Bool {
        let pid: pid_t
        if let targetPID = targetPID {
            pid = targetPID
        } else {
            guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
                print("[AX] No frontmost app")
                return false
            }
            pid = frontmostApp.processIdentifier
        }

        let axApp = AXUIElementCreateApplication(pid)

        var focusedElementRef: AnyObject?
        let copyResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElementRef)
        guard copyResult == .success, let focusedElement = focusedElementRef else {
            print("[AX] No focused UI element (err \(copyResult.rawValue))")
            return false
        }

        // The focused element may be a window/group rather than the text control itself
        // (e.g. TextEdit). Resolve down to an actual editable text element when needed.
        let element = resolveTextElement(focusedElement as! AXUIElement)

        var role: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let roleStr = (role as? String) ?? "?"

        // Preferred: set selected text (inserts at cursor or replaces selection).
        var settable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        if settableResult == .success && settable.boolValue {
            let setResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            if setResult == .success {
                print("[AX] Injected via selectedText into role=\(roleStr)")
                return true
            }
            print("[AX] selectedText set failed (err \(setResult.rawValue)) on role=\(roleStr)")
        }

        // Fallback: append to the value attribute (overwrites/sets full value).
        var valueSettable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &valueSettable)
        if valueSettable.boolValue {
            // Preserve existing content + append, so we don't wipe the field.
            var current: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &current)
            let existing = (current as? String) ?? ""
            let newValue = existing + text
            let setResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue as CFTypeRef)
            if setResult == .success {
                print("[AX] Injected via value attribute into role=\(roleStr)")
                return true
            }
            print("[AX] value set failed (err \(setResult.rawValue)) on role=\(roleStr)")
            return false
        }

        print("[AX] Focused element (role=\(roleStr)) does not support setting text — caller should use clipboard")
        return false
    }

    /// Walks down from a window/group focused element to the first editable text descendant.
    /// Returns the original element if it's already a text control or none is found.
    private func resolveTextElement(_ element: AXUIElement, depth: Int = 0) -> AXUIElement {
        guard depth < 6 else { return element }

        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? ""

        if role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole {
            return element
        }

        // If this element itself accepts selected text, use it.
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
           settable.boolValue {
            return element
        }

        // Otherwise descend into children looking for a text control.
        var childrenRef: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                var childRole: AnyObject?
                AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &childRole)
                let cr = (childRole as? String) ?? ""
                if cr == kAXTextFieldRole || cr == kAXTextAreaRole {
                    return child
                }
            }
            // Recurse one level for nested layouts (scroll areas, groups).
            for child in children {
                let resolved = resolveTextElement(child, depth: depth + 1)
                if resolved as AnyObject !== child as AnyObject || depth == 0 {
                    var rRole: AnyObject?
                    AXUIElementCopyAttributeValue(resolved, kAXRoleAttribute as CFString, &rRole)
                    let rr = (rRole as? String) ?? ""
                    if rr == kAXTextFieldRole || rr == kAXTextAreaRole {
                        return resolved
                    }
                }
            }
        }

        return element
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
