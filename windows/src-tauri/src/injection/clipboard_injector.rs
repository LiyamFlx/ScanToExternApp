/// Clipboard + Ctrl+V fallback injector.
/// Equivalent of Mac's ClipboardInjector.swift.
///
/// Flow:
///   1. Save current clipboard contents
///   2. Write scan text to clipboard
///   3. Simulate Ctrl+V via enigo
///   4. Restore original clipboard after 300ms
use std::time::Duration;

pub fn inject(text: &str) {
    // Capture and inject on a blocking thread (clipboard APIs require STA on Windows)
    let text = text.to_string();
    std::thread::spawn(move || {
        // Save previous clipboard
        let previous = arboard::Clipboard::new()
            .ok()
            .and_then(|mut cb| cb.get_text().ok());

        // Write scan text
        if let Ok(mut cb) = arboard::Clipboard::new() {
            if cb.set_text(&text).is_err() {
                log::warn!("[Clipboard] Failed to write scan text");
                return;
            }
        }

        // Simulate Ctrl+V
        let mut enigo = enigo::Enigo::new(&enigo::Settings::default()).unwrap();
        use enigo::Keyboard;
        let _ = enigo.key(enigo::Key::Control, enigo::Direction::Press);
        let _ = enigo.key(enigo::Key::Unicode('v'), enigo::Direction::Click);
        let _ = enigo.key(enigo::Key::Control, enigo::Direction::Release);

        log::debug!("[Clipboard] Ctrl+V sent");

        // Restore clipboard after 300ms
        std::thread::sleep(Duration::from_millis(300));
        if let Some(prev) = previous {
            if let Ok(mut cb) = arboard::Clipboard::new() {
                let _ = cb.set_text(prev);
            }
        }
    });
}
