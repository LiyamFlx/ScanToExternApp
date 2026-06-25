/// Windows UI Automation injector — primary text injection method.
/// Equivalent of Mac's AXInjector.swift (AXUIElement).
///
/// Strategy:
///   1. Get the currently focused UI element via UIAutomation
///   2. Try ValuePattern (most input controls: Notepad, Word, Outlook fields)
///   3. Try TextPattern for rich-text controls (Word document body, WordPad)
///   4. Return false → caller falls back to clipboard injector
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

    // Strategy 2: TextPattern — rich text controls (Word body, RichTextBox)
    if let Ok(pattern) = focused.get_pattern::<uiautomation::patterns::UITextPattern>() {
        if let Ok(ranges) = pattern.get_selection() {
            if let Some(range) = ranges.first() {
                match range.insert_text(text) {
                    Ok(_) => {
                        log::debug!("[UIA] TextPattern.insert_text succeeded");
                        return true;
                    }
                    Err(e) => {
                        log::debug!("[UIA] TextPattern.insert_text failed: {}", e);
                    }
                }
            }
        }
    }

    false
}

/// Stub for non-Windows builds (CI on Mac, etc.)
#[cfg(not(windows))]
pub fn inject(_text: &str) -> bool {
    false
}
