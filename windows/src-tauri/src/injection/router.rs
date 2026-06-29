/// InjectionRouter — Windows equivalent of Mac's InjectionRouter.swift
///
/// Priority:
///   1. Always broadcast to WebSocket (browser extension, for web apps)
///   2. If injection_method == "uia": try Windows UI Automation, fallback to clipboard
///   3. If injection_method == "clipboard": clipboard only
use super::websocket_bridge::Clients;

pub fn route_text(text: &str, method: &str, ws_clients: &Clients) {
    // 1. Always broadcast to browser extension (handles Google Docs, web mail, etc.)
    super::websocket_bridge::broadcast(ws_clients, text, &uuid::Uuid::new_v4().to_string());

    // 2. Native app injection
    if method == "clipboard" {
        log::debug!("[Router] Clipboard-only mode");
        super::clipboard_injector::inject(text);
        return;
    }

    // UIA primary → clipboard fallback
    #[cfg(windows)]
    {
        if super::uia_injector::inject(text) {
            log::debug!("[Router] UIA injection succeeded");
        } else {
            log::debug!("[Router] UIA failed, using clipboard fallback");
            super::clipboard_injector::inject(text);
        }
    }

    #[cfg(not(windows))]
    {
        // On non-Windows build targets (CI, dev on Mac), just use clipboard
        super::clipboard_injector::inject(text);
    }
}
