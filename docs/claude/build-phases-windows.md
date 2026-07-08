# ScanToExternApp v5.0 — Build Phase 9 (Windows / Tauri + Rust)

_Verbatim Windows build plan extracted from the original CLAUDE.md. Runs parallel to Mac Phase 8, from week 8._

Phase 9 — Windows Tauri App (Week 8–11)
This phase builds the Windows companion app using Tauri 2.0. It mirrors the Mac app's functionality using Windows-native APIs.

Step 9.1 — Tauri project bootstrap

cd windows/

npm create tauri-app@latest . -- --template vanilla

# Or: cargo install tauri-cli && cargo tauri init

# Cargo.toml dependencies:

# tauri = { version = "2", features = ["tray-icon", "window-all"] }

# tokio = { version = "1", features = ["full"] }

# tokio-tungstenite = "0.21"

# btleplug = "0.11"

# serialport = "4"

# rusqlite = { version = "0.31", features = ["bundled"] }

# uiautomation = "0.3"

# enigo = "0.2"

# reqwest = { version = "0.12", features = ["json", "rustls-tls"] }

# serde = { version = "1", features = ["derive"] }

# serde_json = "1"

# uuid = { version = "1", features = ["v4"] }

Step 9.2 — System tray setup

main.rs:

use tauri::{

    Manager, SystemTray, SystemTrayEvent, SystemTrayMenu, CustomMenuItem,

};

fn main() {

    let tray_menu = SystemTrayMenu::new()

        .add_item(CustomMenuItem::new("status", "Disconnected").disabled())

        .add_native_item(tauri::SystemTrayMenuItem::Separator)

        .add_item(CustomMenuItem::new("history", "History"))

        .add_item(CustomMenuItem::new("settings", "Settings"))

        .add_native_item(tauri::SystemTrayMenuItem::Separator)

        .add_item(CustomMenuItem::new("quit", "Quit"));

    tauri::Builder::default()

        .system_tray(SystemTray::new().with_menu(tray_menu))

        .on_system_tray_event(|app, event| match event {

            SystemTrayEvent::LeftClick { .. } => {

                // Show/hide popover window

                let window = app.get_window("main").unwrap();

                if window.is_visible().unwrap() {

                    window.hide().unwrap();

                } else {

                    window.show().unwrap();

                    window.set_focus().unwrap();

                }

            }

            SystemTrayEvent::MenuItemClick { id, .. } => match id.as_str() {

                "quit" => std::process::exit(0),

                "settings" => { /* open settings window */ }

                "history"  => { /* open history window */ }

                _ => {}

            },

            _ => {}

        })

        .invoke_handler(tauri::generate_handler![

            inject_text,

            get_history,

            get_settings,

            save_settings,

        ])

        .run(tauri::generate_context!())

        .expect("error while running Tauri application");

}

Step 9.3 — Windows UI Automation injector (primary)

injection/uia_injector.rs:

use uiautomation::{UIAutomation, UIElement};

pub fn inject(text: &str) -> bool {

    let automation = match UIAutomation::new() {

        Ok(a) => a,

        Err(_) => return false,

    };

    // Get the element with keyboard focus

    let focused = match automation.get_focused_element() {

        Ok(el) => el,

        Err(_) => return false,

    };

    // Check if element supports ValuePattern (text input)

    if let Ok(pattern) = focused.get_pattern::<uiautomation::patterns::UIValuePattern>() {

        // Get current value and append at cursor

        // UIA ValuePattern: set value directly

        let current = pattern.get_value().unwrap_or_default();

        // For cursor position, use TextPattern if available

        let _ = pattern.set_value(text); // inserts or replaces selection

        return true;

    }

    // Try TextPattern for rich text controls (Word, WordPad)

    if let Ok(pattern) = focused.get_pattern::<uiautomation::patterns::UITextPattern>() {

        let selection = pattern.get_selection().unwrap_or_default();

        if let Some(range) = selection.first() {

            range.insert_text(text).ok();

            return true;

        }

    }

    false

}

Step 9.4 — Clipboard injector fallback (Windows)

injection/clipboard_injector.rs:

use enigo::{Enigo, KeyboardControllable, Key};

pub fn inject(text: &str) {

    // Save current clipboard

    // Write text to clipboard via arboard crate

    let mut clipboard = arboard::Clipboard::new().unwrap();

    let previous = clipboard.get_text().ok();

    clipboard.set_text(text).unwrap();

    // Simulate Ctrl+V

    let mut enigo = Enigo::new();

    enigo.key_down(Key::Control);

    enigo.key_click(Key::Layout('v'));

    enigo.key_up(Key::Control);

    // Restore clipboard after 300ms

    std::thread::spawn(move || {

        std::thread::sleep(std::time::Duration::from_millis(300));

        if let Some(prev) = previous {

            if let Ok(mut cb) = arboard::Clipboard::new() {

                let _ = cb.set_text(prev);

            }

        }

    });

}

Step 9.5 — Bluetooth manager (Windows)

hardware/bluetooth.rs:

use btleplug::api::{Central, Manager as _, Peripheral as _, ScanFilter, CharacteristicWriteType};

use btleplug::platform::{Adapter, Manager, Peripheral};

use uuid::Uuid;

const NUS_SERVICE:    Uuid = uuid::uuid!("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");

const NUS_TX_CHAR:    Uuid = uuid::uuid!("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");

pub async fn start_scanning(tx: tokio::sync::mpsc::Sender<String>) {

    let manager = Manager::new().await.unwrap();

    let adapters = manager.adapters().await.unwrap();

    let adapter = adapters.into_iter().next().unwrap();

    adapter.start_scan(ScanFilter::default()).await.unwrap();

    loop {

        let peripherals = adapter.peripherals().await.unwrap();

        for p in peripherals {

            if let Ok(Some(props)) = p.properties().await {

                // Look for Scanmarker by name or service UUID

                if props.local_name.as_deref().unwrap_or("").contains("Scanmarker")

                    || props.services.contains(&NUS_SERVICE) {

                    connect_and_listen(p, tx.clone()).await;

                }

            }

        }

        tokio::time::sleep(std::time::Duration::from_secs(2)).await;

    }

}

async fn connect_and_listen(peripheral: Peripheral, tx: tokio::sync::mpsc::Sender<String>) {

    peripheral.connect().await.ok();

    peripheral.discover_services().await.ok();

    let chars = peripheral.characteristics();

    let tx_char = chars.iter().find(|c| c.uuid == NUS_TX_CHAR).cloned();

    if let Some(ch) = tx_char {

        peripheral.subscribe(&ch).await.ok();

        let mut buffer = String::new();

        let mut last_received = std::time::Instant::now();

        let mut stream = peripheral.notifications().await.unwrap();

        while let Some(data) = stream.next().await {

            buffer.push_str(&String::from_utf8_lossy(&data.value));

            last_received = std::time::Instant::now();

            // Emit complete scan after 300ms silence

            tokio::time::sleep(std::time::Duration::from_millis(300)).await;

            if last_received.elapsed() >= std::time::Duration::from_millis(280) && !buffer.is_empty() {

                let _ = tx.send(buffer.trim().to_string()).await;

                buffer.clear();

            }

        }

    }

}

Step 9.6 — WebSocket server (Windows — identical protocol to Mac)

injection/websocket_bridge.rs:

use tokio_tungstenite::tungstenite::Message;

use std::sync::{Arc, Mutex};

use tokio::net::TcpListener;

pub type Clients = Arc<Mutex<Vec<tokio::sync::mpsc::UnboundedSender<Message>>>>;

pub async fn start_server(clients: Clients) {

    // Bind to localhost ONLY

    let listener = TcpListener::bind("127.0.0.1:52731").await.unwrap();

    while let Ok((stream, addr)) = listener.accept().await {

        // Reject non-localhost connections

        if !addr.ip().is_loopback() { continue; }

        let clients = clients.clone();

        tokio::spawn(async move {

            let ws = tokio_tungstenite::accept_async(stream).await.unwrap();

            let (tx, _rx) = tokio::sync::mpsc::unbounded_channel();

            clients.lock().unwrap().push(tx);

            // Handle messages (ping/ack)

        });

    }

}

pub fn broadcast(clients: &Clients, text: &str, id: &str) {

    let msg = serde_json::json!({

        "type": "scan",

        "text": text,

        "id": id

    }).to_string();

    clients.lock().unwrap().retain(|client| {

        client.send(Message::Text(msg.clone())).is_ok()

    });

}

Step 9.7 — Preview toast window (Windows)

preview/preview_window.rs:

Create a Tauri window: frameless, always-on-top, positioned bottom-right
tauri.conf.json window config:

{

  "label": "preview",

  "title": "",

  "width": 360,

  "height": 140,

  "decorations": false,

  "alwaysOnTop": true,

  "skipTaskbar": true,

  "visible": false,

  "resizable": false

}

Frontend: same PreviewView concept — HTML/CSS with Inject / Edit / Discard buttons
Auto-dismiss: setTimeout(() => invoke('auto_inject'), 2000)
Tauri command inject_text(text: String) calls InjectionRouter

Step 9.8 — Scan history (Windows)

history/store.rs:

use rusqlite::{Connection, Result, params};

pub struct ScanHistoryStore {

    conn: Connection,

}

impl ScanHistoryStore {

    pub fn new() -> Self {

        let path = dirs::data_local_dir()

            .unwrap()

            .join("ScanToExternApp/history.sqlite");

        std::fs::create_dir_all(path.parent().unwrap()).ok();

        let conn = Connection::open(path).unwrap();

        conn.execute_batch("

            CREATE TABLE IF NOT EXISTS scan_records (

                id TEXT PRIMARY KEY,

                text TEXT NOT NULL,

                processed_text TEXT,

                timestamp TEXT NOT NULL,

                source TEXT NOT NULL,

                injected_to TEXT,

                ai_mode TEXT

            );

            CREATE INDEX IF NOT EXISTS idx_ts ON scan_records(timestamp DESC);

        ").unwrap();

        Self { conn }

    }

    pub fn save(&self, id: &str, text: &str, source: &str) {

        self.conn.execute(

            "INSERT INTO scan_records (id, text, timestamp, source) VALUES (?1, ?2, datetime('now'), ?3)",

            params![id, text, source],

        ).ok();

    }

    pub fn recent(&self, limit: usize) -> Vec<(String, String, String)> {

        let mut stmt = self.conn.prepare(

            "SELECT id, text, timestamp FROM scan_records ORDER BY timestamp DESC LIMIT ?1"

        ).unwrap();

        stmt.query_map([limit], |row| {

            Ok((row.get(0)?, row.get(1)?, row.get(2)?))

        }).unwrap().filter_map(|r| r.ok()).collect()

    }

}

Step 9.9 — Windows packaging

# Install Tauri CLI

cargo install tauri-cli

# Build Windows installer

cargo tauri build

# Output: target/release/bundle/msi/ScanToExternApp_5.0.0_x64_en-US.msi

#     or: target/release/bundle/nsis/ScanToExternApp_5.0.0_x64-setup.exe

# Sign with EV certificate (required for SmartScreen)

signtool sign /tr http://timestamp.digicert.com /td sha256 /fd sha256 \

  /sha1 <YOUR_CERT_THUMBPRINT> ScanToExternApp_5.0.0_x64_en-US.msi

Step 9.10 — Windows auto-update

// tauri.conf.json

{

  "tauri": {

    "updater": {

      "active": true,

      "endpoints": ["https://your-update-server.com/windows/{{target}}/{{current_version}}"],

      "dialog": true,

      "pubkey": "<your Ed25519 public key from tauri signer generate>"

    }

  }

}


