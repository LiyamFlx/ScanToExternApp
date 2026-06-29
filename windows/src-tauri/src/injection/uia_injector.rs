/// Windows UI Automation injector — primary text injection method.
/// Equivalent of Mac's AXInjector.swift (AXUIElement).
///
/// Strategy:
///   1. Get the currently focused UI element via UIAutomation
///   2. Try ValuePattern (most input controls: Notepad, Outlook fields, search boxes)
///   3. Return false → caller falls back to clipboard injector (Ctrl+V), which
///      handles rich-text controls (Word/WordPad document body) reliably.
///
/// Note: UI Automation's TextPattern is read-only (no insert API in the spec), so
/// rich-text bodies are handled by the clipboard fallback rather than UIA directly.
#[cfg(windows)]
pub fn inject(text: &str) -> bool {
    use uiautomation::UIAutomation;

    let automation = match UIAutomation::new() {
        Ok(a) => a,
        Err(e) => {
            log::warn!("[UIA] Failed to create UIAutomation: {}", e);
            return false;
        }
    };

    // Get element with keyboard focus
    let focused = match automation.get_focused_element() {
        Ok(el) => el,
        Err(e) => {
            log::debug!("[UIA] No focused element: {}", e);
            return false;
        }
    };

    // Strategy 1: ValuePattern — works for most single/multiline inputs
    if let Ok(pattern) = focused.get_pattern::<uiautomation::patterns::UIValuePattern>() {
        match pattern.set_value(text) {
            Ok(_) => {
                log::debug!("[UIA] ValuePattern.set_value succeeded");
                return true;
            }
            Err(e) => {
                log::debug!("[UIA] ValuePattern.set_value failed: {}", e);
            }
        }
    }

    // No ValuePattern (e.g. Word document body, which is a read-only TextPattern
    // control under UIA): signal failure so the router uses the clipboard injector.
    log::debug!("[UIA] focused element has no settable ValuePattern; deferring to clipboard");
    false
}

/// Stub for non-Windows builds (CI on Mac, etc.)
#[cfg(not(windows))]
#[allow(dead_code)]
pub fn inject(_text: &str) -> bool {
    false
}
