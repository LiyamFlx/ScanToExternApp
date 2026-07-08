# ScanToExternApp v5.0 — Constraints & Security

_Verbatim 'What NOT to Build' list and security hardening checklist extracted from the original CLAUDE.md. These are hard constraints; the summary lives in CLAUDE.md._

Security Hardening Checklist
WebSocket server binds to 127.0.0.1 only, never 0.0.0.0
WebSocket messages validated: max text length 100,000 chars, type allowlist
Claude API key stored in Keychain (not UserDefaults): use Security.framework SecKeychainItem
scan2extern:// URL scheme validates caller (check if message comes from own process)
License file permissions: 0600 (owner read/write only) — not 777
No world-writable files anywhere
App Transport Security enabled (HTTPS only for Claude API)
Sparkle uses EdDSA signatures (not DSA)



What NOT to Build
❌ No Qt — replaced by Swift (Mac) + Tauri/Rust (Windows)
❌ No Electron — Tauri is the correct choice for Windows (10× smaller, Rust safety)
❌ No Silicon Labs VCP driver installation — CoreBluetooth/IOKit (Mac) and btleplug/serialport (Windows) handle it natively
❌ No ABBYY FineReader dependency
❌ No pre/post install shell scripts
❌ No scan2extern:// as the sole injection mechanism (keep for backwards compat only)
❌ No chmod 777 on any file (Mac) — no world-writable files on Windows either
❌ No app that appears in the Dock (Mac) or Taskbar (Windows) — tray/menubar only
❌ No cloud OCR calls without explicit user opt-in per session
❌ No single monolithic cross-platform codebase — Mac and Windows are separate native apps sharing only the browser extension and WebSocket protocol


