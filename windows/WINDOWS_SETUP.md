# ScanToExternApp v5.0 — Windows Setup Guide

## Prerequisites

```powershell
# 1. Install Rust
winget install Rustlang.Rustup
rustup update stable
rustup target add x86_64-pc-windows-msvc

# 2. Install Tauri CLI
cargo install tauri-cli --version "^2"

# 3. Install Node.js (only needed for tauri dev tooling)
winget install OpenJS.NodeJS.LTS

# 4. Install Visual Studio Build Tools (required for MSVC linker)
winget install Microsoft.VisualStudio.2022.BuildTools
# During install: select "Desktop development with C++"
```

## Dev Build & Run

```powershell
cd windows/

# Install frontend deps (none required — vanilla HTML)
# Start in dev mode (opens tray + dev tools)
cargo tauri dev
```

> The tray icon appears in the Windows system tray (bottom-right of taskbar).
> Right-click → "Debug: Simulate Scan" to test the full pipeline without hardware.

## Production Build

```powershell
cd windows/
cargo tauri build
# Output: src-tauri/target/release/bundle/msi/ScanToExternApp_5.0.0_x64_en-US.msi
#     or: src-tauri/target/release/bundle/nsis/ScanToExternApp_5.0.0_x64-setup.exe
```

## Code Signing (Required for Windows SmartScreen)

You need an EV Code Signing Certificate (Sectigo / DigiCert / SSL.com).

```powershell
# Sign the MSI with signtool
signtool sign `
  /tr http://timestamp.digicert.com `
  /td sha256 /fd sha256 `
  /sha1 <YOUR_CERT_THUMBPRINT> `
  "src-tauri/target/release/bundle/msi/ScanToExternApp_5.0.0_x64_en-US.msi"
```

## Auto-Update Setup

1. Generate Tauri updater keys:
   ```powershell
   cargo tauri signer generate -w keys/updater.key
   ```
2. Put the **public key** in `tauri.conf.json` → `updater.pubkey`.
3. Keep the **private key** in your CI secrets.
4. Host the update manifest at the endpoint in `tauri.conf.json`.

## Architecture Overview

```
System Tray (Tauri 2.0)
    │
    ├─ Left click → main popover (index.html)
    ├─ Right click → context menu (tray menu)
    │     ├─ History… → history.html window
    │     ├─ Settings… → settings.html window
    │     ├─ Debug: Simulate Scan → triggers full pipeline
    │     └─ Quit
    │
Rust Backend (tokio async)
    │
    ├─ hardware::bluetooth    (btleplug, NUS BLE)
    ├─ hardware::usb_serial   (serialport, COM, 115200)
    │
    ├─ broadcast::channel<(text, source)>
    │
    ├─ Pipeline task:
    │    ai::claude_processor (opt-in) → preview window → confirm_inject
    │
    ├─ injection::uia_injector   (Windows UI Automation — primary)
    ├─ injection::clipboard_injector (enigo Ctrl+V — fallback)
    ├─ injection::websocket_bridge  (ws://127.0.0.1:52731 → Chrome extension)
    │
    └─ history::store (rusqlite SQLite, same schema as Mac)
```

## Browser Extension

The same `BrowserExtension/` from the Mac side works on Windows without changes.
Load it in Chrome:
1. chrome://extensions → Enable Developer mode
2. "Load unpacked" → select `BrowserExtension/`
3. The extension connects to `ws://127.0.0.1:52731` when the Tauri app is running.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `cargo build` fails on `uiautomation` | Requires MSVC target; run `rustup target add x86_64-pc-windows-msvc` |
| `btleplug` BLE not finding device | Enable Bluetooth, check Windows permissions for BLE |
| UI Automation injection fails | Open "Settings" → switch to Clipboard fallback temporarily |
| Tray icon missing | Check `src-tauri/icons/` — must have `icon.ico` |

## Testing Without Hardware

Right-click tray icon → **"Debug: Simulate Scan"**

This sends a test string through the entire pipeline:
AI processing → preview toast (if enabled) → UIA injection → SQLite history
