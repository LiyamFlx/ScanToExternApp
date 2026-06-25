# ScanToExternApp WebSocket Protocol (v1)

**Endpoint**: ws://127.0.0.1:52731
**Direction**: Bidirectional (app is server, browser extension + future tools are clients)

## Message Types (JSON)

### From App → Clients (broadcast on every new scan)
```json
{
  "type": "scan",
  "text": "The scanned text content here...",
  "id": "uuid-v4-string"
}
```

### From Client → App (ack)
```json
{
  "type": "ack",
  "id": "uuid-v4-string"
}
```

### Keep-alive / health
```json
{ "type": "ping" }
```

## Rules
- Only localhost connections accepted (127.0.0.1). Reject all others.
- Text length limit: 100000 characters (reject larger).
- Reassemble logic lives in hardware layer (300ms silence). WS receives complete strings.
- Extension background.js connects, forwards to active tab's content script.
- ACK is optional for now but recommended for future reliability.

## Implementation Notes
- Mac: Network.framework NWListener (pure Apple, no extra deps)
- Windows: tokio-tungstenite (in Tauri)
- Same port/protocol on both → single browser extension works everywhere.

## Backwards
Older scan2extern:// scheme may be supported for compatibility but is **not** the primary mechanism.
