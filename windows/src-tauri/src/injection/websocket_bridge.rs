/// Local WebSocket server — browser extension bridge.
/// Identical JSON protocol to Mac's WebSocketBridge.swift (NWListener).
///
/// Binds ONLY to 127.0.0.1:52731 (localhost guard — never 0.0.0.0).
///
/// Messages:
///   { "type": "scan",  "text": "…", "id": "uuid" }  — app → extension
///   { "type": "ack",   "id": "uuid" }                — extension → app
///   { "type": "ping" }                                — keep-alive
use std::net::SocketAddr;
use std::sync::Arc;
use parking_lot::Mutex;

use futures_util::{SinkExt, StreamExt};
use tauri::AppHandle;
use tokio::net::TcpListener;
use tokio::sync::mpsc::{unbounded_channel, UnboundedSender};
use tokio_tungstenite::{
    accept_hdr_async,
    tungstenite::{
        handshake::server::{ErrorResponse, Request, Response},
        Message,
    },
};

pub type Clients = Arc<Mutex<Vec<UnboundedSender<Message>>>>;

/// Rejects the handshake if the Origin header is an http(s) page origin — i.e. a browser tab,
/// not our extension. Browsers set Origin on WebSocket connects and JS cannot override it, so
/// this is a real (not spoofable) defense against any webpage doing
/// `new WebSocket("ws://127.0.0.1:52731")` to silently read live scan broadcasts.
/// Extension service workers send `chrome-extension://<id>` / `moz-extension://<id>` /
/// `safari-web-extension://<id>`, or sometimes no Origin at all — both allowed.
fn check_origin(req: &Request, resp: Response) -> Result<Response, ErrorResponse> {
    if let Some(origin) = req.headers().get("Origin").and_then(|v| v.to_str().ok()) {
        if origin.starts_with("http://") || origin.starts_with("https://") {
            log::warn!("[WS] Rejected handshake from page origin: {}", origin);
            return Err(ErrorResponse::new(Some(
                "Rejected: connections from web pages are not allowed".into(),
            )));
        }
    }
    Ok(resp)
}

pub async fn start_server(clients: Clients, _app: AppHandle) {
    // SECURITY: bind to loopback only — refuse connections from LAN/internet
    let addr: SocketAddr = "127.0.0.1:52731".parse().unwrap();

    let listener = match TcpListener::bind(addr).await {
        Ok(l) => {
            log::info!("[WS] Server listening on ws://{}", addr);
            l
        }
        Err(e) => {
            log::error!("[WS] Failed to bind: {}", e);
            return;
        }
    };

    loop {
        match listener.accept().await {
            Ok((stream, peer_addr)) => {
                // Reject non-localhost connections
                if !peer_addr.ip().is_loopback() {
                    log::warn!("[WS] Rejected non-localhost connection from {}", peer_addr);
                    continue;
                }

                let clients = clients.clone();
                tauri::async_runtime::spawn(async move {
                    handle_client(stream, clients, peer_addr).await;
                });
            }
            Err(e) => {
                log::warn!("[WS] Accept error: {}", e);
            }
        }
    }
}

async fn handle_client(
    raw: tokio::net::TcpStream,
    clients: Clients,
    addr: SocketAddr,
) {
    let ws = match accept_hdr_async(raw, check_origin).await {
        Ok(ws) => ws,
        Err(e) => {
            log::warn!("[WS] Handshake failed from {}: {}", addr, e);
            return;
        }
    };

    log::info!("[WS] Extension connected from {}", addr);

    let (tx, mut rx) = unbounded_channel::<Message>();
    clients.lock().push(tx);

    let (mut write, mut read) = ws.split();

    // Task: forward queued outbound messages to the WebSocket
    let write_task = tauri::async_runtime::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if write.send(msg).await.is_err() {
                break;
            }
        }
    });

    // Read incoming messages (ack, ping)
    while let Some(msg_result) = read.next().await {
        match msg_result {
            Ok(Message::Text(raw)) => {
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&raw) {
                    let msg_type = json["type"].as_str().unwrap_or("");
                    match msg_type {
                        "ack" => log::debug!("[WS] ACK id={}", json["id"]),
                        "ping" => log::debug!("[WS] Ping from extension"),
                        _ => log::debug!("[WS] Unknown message type: {}", msg_type),
                    }
                }
            }
            Ok(Message::Close(_)) | Err(_) => break,
            _ => {}
        }
    }

    // Remove this client on disconnect
    clients.lock().retain(|c| !c.is_closed());
    write_task.abort();
    log::info!("[WS] Extension disconnected from {}", addr);
}

/// Broadcast a scan to all connected extension clients.
/// Removes dead clients automatically.
pub fn broadcast(clients: &Clients, text: &str, id: &str) {
    // Validate: max 100,000 chars (security hardening)
    if text.len() > 100_000 {
        log::warn!("[WS] Scan text too long ({}), truncating broadcast", text.len());
        return;
    }

    let msg = serde_json::json!({
        "type": "scan",
        "text": text,
        "id": id,
    })
    .to_string();

    let mut clients_guard = clients.lock();
    clients_guard.retain(|client| {
        client.send(Message::Text(msg.clone())).is_ok()
    });

    log::debug!("[WS] Broadcast to {} clients", clients_guard.len());
}
