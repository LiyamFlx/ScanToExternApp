/// Clipboard + Ctrl+V fallback injector.
/// Equivalent of Mac's ClipboardInjector.swift.
///
/// Flow:
///   1. Save current clipboard contents (only if no injection is already in flight)
///   2. Write scan text to clipboard
///   3. Simulate Ctrl+V via enigo
///   4. Restore original clipboard after 300ms — but only if no newer injection has
///      started since, otherwise skip (the newer injection owns the restore).
use std::sync::atomic::{AtomicU64, Ordering};
use parking_lot::Mutex;
use std::sync::OnceLock;
use std::time::Duration;

static GENERATION: AtomicU64 = AtomicU64::new(0);
static SAVED_CLIPBOARD: OnceLock<Mutex<Option<String>>> = OnceLock::new();

pub fn inject(text: &str) {
    let text = text.to_string();
    let saved = SAVED_CLIPBOARD.get_or_init(|| Mutex::new(None));

    // Claim this generation. Only the first injection in a burst captures "previous";
    // later ones in the same burst skip the capture (it'd just be the prior scan text)
    // and every injection except the last one skips the restore.
    let my_gen = GENERATION.fetch_add(1, Ordering::SeqCst) + 1;

    {
        let mut guard = saved.lock();
        if guard.is_none() {
            *guard = Some(
                arboard::Clipboard::new()
                    .ok()
                    .and_then(|mut cb| cb.get_text().ok())
                    .unwrap_or_default(),
            );
        }
    }

    std::thread::spawn(move || {
        if let Ok(mut cb) = arboard::Clipboard::new() {
            if cb.set_text(&text).is_err() {
                log::warn!("[Clipboard] Failed to write scan text");
                return;
            }
        }

        match enigo::Enigo::new(&enigo::Settings::default()) {
            Ok(mut enigo) => {
                use enigo::Keyboard;
                let _ = enigo.key(enigo::Key::Control, enigo::Direction::Press);
                let _ = enigo.key(enigo::Key::Unicode('v'), enigo::Direction::Click);
                let _ = enigo.key(enigo::Key::Control, enigo::Direction::Release);
                log::debug!("[Clipboard] Ctrl+V sent");
            }
            Err(e) => {
                log::warn!("[Clipboard] Failed to init input simulation (no active desktop session?): {}", e);
                return;
            }
        }

        std::thread::sleep(Duration::from_millis(300));

        // Only the most recent injection restores. If a newer scan started while we slept,
        // it now owns the eventual restore — bail out instead of clobbering its write.
        if GENERATION.load(Ordering::SeqCst) != my_gen {
            log::debug!("[Clipboard] Newer injection superseded this restore, skipping");
            return;
        }

        let previous = SAVED_CLIPBOARD
            .get_or_init(|| Mutex::new(None))
            .lock()
            .take();
        if let Some(prev) = previous {
            if let Ok(mut cb) = arboard::Clipboard::new() {
                let _ = cb.set_text(prev);
            }
        }
    });
}
