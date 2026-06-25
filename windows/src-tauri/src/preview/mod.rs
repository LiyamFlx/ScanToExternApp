/// Preview toast window management.
/// Equivalent of Mac's PreviewWindowController.swift.
///
/// The preview window (label: "preview") is a frameless always-on-top Tauri
/// WebView window positioned bottom-right of the primary monitor.
/// preview.html drives the UI; it calls back via Tauri commands.
use tauri::{AppHandle, Manager, PhysicalPosition, PhysicalSize, WebviewWindow};

/// Position the preview window at the bottom-right of the primary monitor,
/// with an 20px margin. Called before showing the window.
pub fn position_bottom_right(window: &WebviewWindow) {
    if let Ok(Some(monitor)) = window.primary_monitor() {
        let screen_size = monitor.size();
        let win_size = PhysicalSize {
            width: 360_u32,
            height: 150_u32,
        };
        let scale = monitor.scale_factor();
        let margin = (20.0 * scale) as u32;

        let x = screen_size.width.saturating_sub(win_size.width + margin) as i32;
        let y = screen_size.height.saturating_sub(win_size.height + margin) as i32;

        let _ = window.set_size(tauri::Size::Physical(win_size));
        let _ = window.set_position(PhysicalPosition { x, y });
    }
}

/// Tauri command: user clicked "Inject" in the preview window.
/// Performs actual injection and saves to history.
#[tauri::command]
pub fn confirm_inject(
    text: String,
    app: AppHandle,
    state: tauri::State<std::sync::Arc<crate::AppState>>,
) {
    let settings = state.settings.read().unwrap().clone();

    // Hide preview
    if let Some(pw) = app.get_webview_window("preview") {
        let _ = pw.hide();
    }

    // Inject
    crate::injection::router::route_text(&text, &settings.injection_method, &state.ws_clients);

    // History
    if settings.history_enabled {
        let record = crate::history::store::ScanRecord {
            id: uuid::Uuid::new_v4().to_string(),
            text: text.clone(),
            processed_text: None,
            timestamp: chrono::Utc::now().to_rfc3339(),
            source: "preview".to_string(),
            injected_to: None,
            ai_mode: Some(settings.ai_mode.clone()),
        };
        let _ = state.history.lock().unwrap().save(&record);
    }

    log::info!("[Preview] Injected {} chars", text.len());
}

/// Tauri command: user clicked "Discard" in the preview window.
#[tauri::command]
pub fn discard_preview(app: AppHandle) {
    if let Some(pw) = app.get_webview_window("preview") {
        let _ = pw.hide();
    }
    log::info!("[Preview] Discarded by user");
}
