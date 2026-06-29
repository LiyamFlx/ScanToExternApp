# ScanToExternApp — Windows build, for team review

**Version:** 5.0.0 · **Built:** 2026-06-29 on Windows 11 (x64) · **Status:** first runnable Windows build.

This is the Tauri 2.0 system-tray companion (Rust backend + static HTML UI). It mirrors
the macOS app and shares the browser extension + WebSocket protocol.

## How to install (easiest)

Use the per-user NSIS installer — **no admin required**:

```
ScanToExternApp_5.0.0_x64-setup.exe      (~4.5 MB, NSIS, installs for current user)
ScanToExternApp_5.0.0_x64_en-US.msi      (~6.4 MB, MSI, machine install)
```

> ⚠️ The build is **not code-signed yet**, so Windows SmartScreen will show
> "Windows protected your PC" → click **More info → Run anyway**. A real EV
> code-signing cert removes this (tracked as a distribution to-do, see HANDOFF.md).

After install, the app starts as a **tray icon** (no taskbar/Start window). Left-click
the tray icon for the popover; right-click for History / Settings / Quit.

## Verify it works without the Scanmarker hardware (self-test)

The app has a built-in injection self-test. From a terminal:

```powershell
$env:STEA_SELFTEST = "1"
& "C:\Program Files\ScanToExternApp\ScanToExternApp.exe"   # or the installed path
```

Within ~8 seconds it fires a synthetic scan and injects the text
`ScanToExternApp self-test injection OK` into **whatever text field is focused**.
Open Notepad/Word, click into it, and watch the text appear. (Preview is disabled in
self-test mode so it injects directly.) Unset the variable / restart normally for real use.

## What is verified ✅

| Area | Status |
|---|---|
| Compiles & links on Windows (MSVC) | ✅ |
| App launches as tray app, stays resident | ✅ |
| **Text injection into the focused external app** | ✅ verified live (clipboard Ctrl+V path) |
| Foreground-window capture/restore (inject targets the user's app, not our preview) | ✅ added + working |
| WebSocket bridge `ws://127.0.0.1:52731` (browser-extension link) | ✅ binds IPv4, accepts clients |
| SQLite scan history (`%LOCALAPPDATA%\ScanToExternApp\history.sqlite`) | ✅ initializes |
| Bluetooth stack (btleplug) scanning & device discovery | ✅ discovers BLE devices, incl. a Nordic-UART device |
| MSI + NSIS installers produced | ✅ |

## What still needs hardware / a human to confirm ⚠️

| Area | Note |
|---|---|
| **Pairing + scanning with a real Scanmarker pen (BLE)** | The BT layer works and previously *found* a Nordic-UART device ("M1_C5C0") but the connect didn't complete. On Windows, BLE devices usually must be **paired in Windows Settings → Bluetooth first**, and the pen must be awake/in range. Needs a real pen to confirm end-to-end scan → inject. |
| **USB Scanmarker (Silicon Labs VCP)** | Code looks for VID `0x10C4` at 115200 8N1. No USB pen was connected to this machine, so untested. |
| Preview toast UX, History/Settings windows | Render and are wired (events + commands), but not click-tested by a human yet. |
| Claude AI cloud mode | Code path present (opt-in, user API key in Windows Credential Manager); not exercised. |
| Browser extension end-to-end (Google Docs, Gmail) | Bridge accepts connections; pair with `BrowserExtension/` and confirm injection in-page. |

## Build from source (on a Windows machine)

Prereqs: Rust (MSVC toolchain), Visual Studio C++ Build Tools + Windows SDK, WebView2 (preinstalled on Win 11).

```powershell
cd windows\src-tauri
cargo run            # dev: compile + launch the tray app
cargo tauri build    # produce target\release\bundle\{msi,nsis}\
```

No Node.js needed — the frontend is static HTML in `windows\src`.
