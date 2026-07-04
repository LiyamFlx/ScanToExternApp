/// Windows UI Automation injector — primary text injection method.
/// Equivalent of Mac's AXInjector.swift (AXUIElement).
///
/// Strategy:
///   1. Get the currently focused UI element via UIAutomation
///   2. Try ValuePattern (most input controls: Notepad, Word, Outlook fields)
///   3. Fall back to clipboard (router.rs) — TextPattern has no write method
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

    // Strategy 2: TextPattern exists on rich-text controls (Word body, RichTextBox)
    // but ITextRangeProvider has no write method (GetText/Select/Move only — it's
    // read/selection-oriented). There is no UIA-native way to insert text into a
    // TextPattern-only control; router.rs falls back to clipboard+Ctrl-V for these.

    false
}

/// Stub for non-Windows builds (CI on Mac, etc.)
#[cfg(not(windows))]
#[allow(dead_code)]
pub fn inject(_text: &str) -> bool {
    false
}
