// ScanToExternApp v5.0 — Windows Tauri 2.0 entry point
// Phase 9: System tray app mirroring Mac menubar app functionality.
//
// Architecture:
//   - Tauri manages the tray icon + 4 webview windows (main popover, preview toast,
//     settings, history)
//   - tokio tasks handle Bluetooth (btleplug) and USB serial (serialport) in background
//   - WebSocket server (tokio-tungstenite) on 127.0.0.1:52731 bridges to browser extension
//   - Windows UI Automation API (uiautomation crate) is the primary injector
//   - enigo + arboard provide clipboard Ctrl+V fallback
//   - rusqlite stores scan history (same schema as Mac)

// Prevents console window on Windows in release builds
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod hardware;
mod injection;
mod ai;
mod history;
mod preview;

use std::sync::{Arc, Mutex, RwLock};
use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager,
};
use tokio::sync::broadcast;

use history::store::ScanHistoryStore;
use injection::websocket_bridge::Clients;

// ── Shared application state ──────────────────────────────────────────────────

#[derive(Debug, Clone, serde::Serialize)]
pub struct ConnectionStatus {
    pub connected: bool,
    pub device_name: String,
    pub source: String, // "bluetooth" | "usb" | ""
}

impl Default for ConnectionStatus {
    fn default() -> Self {
        Self {
            connected: false,
            device_name: String::new(),
            source: String::new(),
        }
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AppSettings {
    pub preview_enabled: bool,
    pub preview_timeout_ms: u64,
    pub ai_mode: String,        // "off" | "correct" | "translate" | "summarize" | "custom"
    pub target_language: String,
    pub history_enabled: bool,
    pub history_limit: usize,
    pub prefer_bluetooth: bool,
    pub injection_method: String, // "uia" | "clipboard"
    pub claude_api_key: String,   // loaded from Windows Credential Manager at runtime
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            preview_enabled: true,
            preview_timeout_ms: 2000,
            ai_mode: "off".into(),
            target_language: "English".into(),
            history_enabled: true,
            history_limit: 500,
            prefer_bluetooth: true,
            injection_method: "uia".into(),
            claude_api_key: String::new(),
        }
    }
}

pub struct AppState {
    pub settings: Arc<RwLock<AppSettings>>,
    pub connection: Arc<RwLock<ConnectionStatus>>,
    pub history: Arc<Mutex<ScanHistoryStore>>,
    pub ws_clients: Clients,
    pub scan_tx: broadcast::Sender<(String, String)>, // (text, source)
}

// ── Tauri commands (callable from frontend via invoke()) ───────────────────────

#[tauri::command]
fn get_status(state: tauri::State<Arc<AppState>>) -> ConnectionStatus {
    state.connection.read().unwrap().clone()
}

#[tauri::command]
fn get_settings(state: tauri::State<Arc<AppState>>) -> AppSettings {
    state.settings.read().unwrap().clone()
}

#[tauri::command]
fn save_settings(new_settings: AppSettings, state: tauri::State<Arc<AppState>>) {
    let api_key = new_settings.claude_api_key.clone();

    // Persist API key to secure credential store (Keychain / Credential Manager)
    if !api_key.is_empty() {
        ai::credential_store::save_api_key(&api_key).ok();
    }

    let mut s = state.settings.write().unwrap();
    *s = new_settings;
    s.claude_api_key = String::new(); // don't keep in memory beyond necessity

    log::info!("[Settings] Saved");
}

#[tauri::command]
fn inject_text(text: String, state: tauri::State<Arc<AppState>>) {
    let method = state.settings.read().unwrap().injection_method.clone();
    injection::router::route_text(&text, &method, &state.ws_clients);
}

#[tauri::command]
fn simulate_scan(app: AppHandle, state: tauri::State<Arc<AppState>>) {
    let text = "Hello from ScanToExternApp v5.0 — Windows debug scan!".to_string();
    log::info!("[Debug] Simulated scan: {}", text);
    let _ = state.scan_tx.send((text, "debug".to_string()));
    let _ = app.emit("scan-received", ());
}

#[tauri::command]
fn get_history(
    limit: usize,
    state: tauri::State<Arc<AppState>>,
) -> Vec<history::store::ScanRecord> {
    state
        .history
        .lock()
        .unwrap()
        .recent(limit)
        .unwrap_or_default()
}

#[tauri::command]
fn search_history(
    query: String,
    state: tauri::State<Arc<AppState>>,
) -> Vec<history::store::ScanRecord> {
    state
        .history
        .lock()
        .unwrap()
        .search(&query)
        .unwrap_or_default()
}

#[tauri::command]
fn clear_history(state: tauri::State<Arc<AppState>>) {
    let _ = state.history.lock().unwrap().delete_all();
}

#[tauri::command]
fn re_inject_record(id: String, app: AppHandle, state: tauri::State<Arc<AppState>>) {
    let record = state
        .history
        .lock()
        .unwrap()
        .get_by_id(&id)
        .unwrap_or_default();
    if let Some(r) = record {
        let text = r.processed_text.unwrap_or(r.text);
        let _ = state.scan_tx.send((text, "history".to_string()));
        let _ = app.emit("scan-received", ());
    }
}

// ── Main ──────────────────────────────────────────────────────────────────────

fn main() {
    env_logger::Builder::from_default_env()
        .filter_level(log::LevelFilter::Info)
        .init();

    // Shared state initialised before Tauri builder
    let settings = Arc::new(RwLock::new({
        let mut s = AppSettings::default();
        // Load API key from secure store (Keychain on Mac, Credential Manager on Windows)
        if let Ok(key) = ai::credential_store::load_api_key() {
            s.claude_api_key = key;
        }
        s
    }));

    let history = Arc::new(Mutex::new(ScanHistoryStore::new()));
    let ws_clients: Clients = Arc::new(Mutex::new(vec![]));
    let connection = Arc::new(RwLock::new(ConnectionStatus::default()));
    let (scan_tx, _) = broadcast::channel::<(String, String)>(64);

    let app_state = Arc::new(AppState {
        settings: settings.clone(),
        connection: connection.clone(),
        history: history.clone(),
        ws_clients: ws_clients.clone(),
        scan_tx: scan_tx.clone(),
    });

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(app_state.clone())
        .setup(move |app| {
            // ── Tray icon + menu ──────────────────────────────────────────
            let status_item =
                MenuItem::with_id(app, "status", "⚡ Disconnected", false, None::<&str>)?;
            let sep1 = PredefinedMenuItem::separator(app)?;
            let history_item = MenuItem::with_id(app, "history", "History…", true, None::<&str>)?;
            let settings_item =
                MenuItem::with_id(app, "settings", "Settings…", true, None::<&str>)?;
            let debug_item =
                MenuItem::with_id(app, "debug", "Debug: Simulate Scan", true, None::<&str>)?;
            let sep2 = PredefinedMenuItem::separator(app)?;
            let quit_item = PredefinedMenuItem::quit(app, Some("Quit ScanToExternApp"))?;

            let menu = Menu::with_items(
                app,
                &[
                    &status_item,
                    &sep1,
                    &history_item,
                    &settings_item,
                    &debug_item,
                    &sep2,
                    &quit_item,
                ],
            )?;

            let _tray = TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .menu(&menu)
                .tooltip("ScanToExternApp")
                .on_menu_event({
                    let app_handle = app.handle().clone();
                    move |_tray, event| match event.id.as_ref() {
                        "history" => {
                            if let Some(w) = app_handle.get_webview_window("history") {
                                let _ = w.show();
                                let _ = w.set_focus();
                            }
                        }
                        "settings" => {
                            if let Some(w) = app_handle.get_webview_window("settings") {
                                let _ = w.show();
                                let _ = w.set_focus();
                            }
                        }
                        "debug" => {
                            let text =
                                "Hello from ScanToExternApp v5.0 — Windows debug scan!".to_string();
                            let _ = scan_tx.send((text, "debug".to_string()));
                            let _ = app_handle.emit("scan-received", ());
                        }
                        _ => {}
                    }
                })
                .on_tray_icon_event({
                    let app_handle = app.handle().clone();
                    move |_tray, event| {
                        if let TrayIconEvent::Click {
                            button: MouseButton::Left,
                            button_state: MouseButtonState::Up,
                            ..
                        } = event
                        {
                            if let Some(window) = app_handle.get_webview_window("main") {
                                if window.is_visible().unwrap_or(false) {
                                    let _ = window.hide();
                                } else {
                                    let _ = window.show();
                                    let _ = window.set_focus();
                                }
                            }
                        }
                    }
                })
                .build(app)?;

            // ── WebSocket server (browser extension bridge) ────────────────
            let ws_clients_clone = ws_clients.clone();
            let app_handle_ws = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                injection::websocket_bridge::start_server(ws_clients_clone, app_handle_ws).await;
            });

            // ── Hardware: Bluetooth ───────────────────────────────────────
            let scan_tx_bt = app_state.scan_tx.clone();
            let conn_bt = connection.clone();
            tauri::async_runtime::spawn(async move {
                hardware::bluetooth::start(scan_tx_bt, conn_bt).await;
            });

            // ── Hardware: USB serial ──────────────────────────────────────
            let scan_tx_usb = app_state.scan_tx.clone();
            let conn_usb = connection.clone();
            tauri::async_runtime::spawn(async move {
                hardware::usb_serial::start(scan_tx_usb, conn_usb).await;
            });

            // ── Scan pipeline subscriber ──────────────────────────────────
            // Each scan from any hardware source flows through preview → AI → inject → history
            let mut scan_rx = app_state.scan_tx.subscribe();
            let pipeline_state = app_state.clone();
            let app_handle_pipeline = app.handle().clone();

            tauri::async_runtime::spawn(async move {
                while let Ok((raw_text, source)) = scan_rx.recv().await {
                    log::info!("[Pipeline] Scan received ({} chars) via {}", raw_text.len(), source);

                    let settings = pipeline_state.settings.read().unwrap().clone();

                    // AI processing (cloud opt-in)
                    let processed = if settings.ai_mode != "off" && !settings.claude_api_key.is_empty() {
                        match ai::claude_processor::process(
                            &raw_text,
                            &settings.ai_mode,
                            &settings.target_language,
                            &settings.claude_api_key,
                        )
                        .await
                        {
                            Ok(p) => p,
                            Err(e) => {
                                log::warn!("[AI] Processing failed: {}", e);
                                raw_text.clone()
                            }
                        }
                    } else {
                        raw_text.clone()
                    };

                    // Preview toast or direct inject
                    if settings.preview_enabled {
                        // Show preview window, pass text via event
                        if let Some(pw) = app_handle_pipeline.get_webview_window("preview") {
                            // Position bottom-right of primary monitor
                            preview::position_bottom_right(&pw);
                            let _ = pw.emit("preview-text", &processed);
                            let _ = pw.show();
                            let _ = pw.set_focus();
                        }
                        // preview.html handles inject/discard and calls back via tauri command
                    } else {
                        // Direct inject path
                        injection::router::route_text(
                            &processed,
                            &settings.injection_method,
                            &pipeline_state.ws_clients,
                        );

                        // History
                        if settings.history_enabled {
                            let record = history::store::ScanRecord {
                                id: uuid::Uuid::new_v4().to_string(),
                                text: raw_text.clone(),
                                processed_text: if processed != raw_text {
                                    Some(processed.clone())
                                } else {
                                    None
                                },
                                timestamp: chrono::Utc::now().to_rfc3339(),
                                source: source.clone(),
                                injected_to: None,
                                ai_mode: Some(settings.ai_mode.clone()),
                            };
                            let _ = pipeline_state.history.lock().unwrap().save(&record);
                        }
                    }

                    // Notify popover of last scan
                    let _ = app_handle_pipeline.emit("last-scan", &processed);
                }
            });

            log::info!("[ScanToExternApp] v5.0 Windows tray app started");
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_status,
            get_settings,
            save_settings,
            inject_text,
            simulate_scan,
            get_history,
            search_history,
            clear_history,
            re_inject_record,
            preview::confirm_inject,
            preview::discard_preview,
        ])
        .run(tauri::generate_context!())
        .expect("error while running ScanToExternApp");
}
