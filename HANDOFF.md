# Project Handoff — read this first

Status notes for continuing work across machines/sessions. Last updated: 2026-06-29.

## TL;DR of where things stand

- **Mac app: WORKS and is verified.** Native text injection (Accessibility + clipboard)
  passes an automated self-test. WebSocket bridge to the browser extension works.
  A signed DMG was built (`ScanToExternApp-5.0.0.dmg`, ~2.2 MB).
- **Windows app: written and compiles, but NEVER built into a runnable app or tested.**
  It must be built ON a Windows machine — it cannot be built or run on macOS.
- All fixes are committed to `master` (commit "Fix WebSocket IPv4 binding, remove
  Sparkle, verify native injection").

## What was fixed this session (Mac)

1. **WebSocket server bound IPv6-only** → Chrome/the extension (which use IPv4
   127.0.0.1) hung forever and never got scans. Rewrote `mac/.../WebSocketBridge.swift`
   as a clean RFC 6455 server with an explicit IPv4 loopback bind. Verified: a client
   completes the handshake and receives scan messages.
   - NOTE: the Windows WS server (`windows/src-tauri/src/injection/websocket_bridge.rs`)
     already binds `127.0.0.1` (IPv4) correctly — it does NOT have this bug.
2. **Removed Sparkle entirely.** Its updater crashed on launch ("updater failed to
   start") and its framework signing broke the self-signed build. Auto-update isn't
   needed for hand-distributed builds.
3. **Native injection verified** via the app's built-in self-test (opens TextEdit,
   injects, reads back) → AX=PASS, Clipboard=PASS.
4. **Hardened the MV3 browser extension** (`BrowserExtension/background.js`) with
   `chrome.alarms` keepalive so the service worker dying after ~30s idle no longer
   silently drops scans.

## How to build + run the MAC app

```bash
cd mac
# Regenerate the Xcode project from project.yml if needed (requires `brew install xcodegen`):
xcodegen generate
# Build Release:
xcodebuild -project ScanToExternApp.xcodeproj -scheme ScanToExternApp -configuration Release \
  -derivedDataPath build build
# App is at: build/Build/Products/Release/ScanToExternApp.app
```
Sign with the local self-signed cert (created once via `mac/make-signing-cert.sh`):
```bash
codesign --force --sign "ScanToExternApp Self-Signed" --options runtime \
  build/Build/Products/Release/ScanToExternApp.app
```
Self-test injection (opens TextEdit, injects, writes PASS/FAIL to ~/Desktop/scanapp-selftest.txt):
```bash
SCANAPP_SELFTEST=1 build/Build/Products/Release/ScanToExternApp.app/Contents/MacOS/ScanToExternApp
```

## How to build the WINDOWS app (MUST be done on Windows)

The Rust code compiles (verified via `cargo check` on Mac), but the Windows-only
injection/tray/installer code only builds on Windows. On a Windows 10/11 PC:

```powershell
# Prereqs: install Rust (rustup), Node.js, and the Tauri CLI:
#   https://tauri.app/start/prerequisites/  (needs MSVC build tools + WebView2)
cargo install tauri-cli

cd windows\src-tauri
# Dev run (launches the tray app):
cargo tauri dev
# Production installer (.msi / .exe):
cargo tauri build
# Output: target\release\bundle\msi\  and  target\release\bundle\nsis\
```
Then test on Windows: tray icon appears, Scanmarker connects (BT/USB), scanning
injects into Notepad/Word via UI Automation, browser extension connects, etc.
See `windows/WINDOWS_SETUP.md` and the acceptance criteria in `CLAUDE.md` (Sprint 4).

## What still needs deciding (distribution)

For users to "just open it" with no warnings:
- **Mac:** needs an Apple Developer ID cert ($99/yr) + notarization. Without it, the
  self-signed DMG opens but each user must right-click → Open, and web-downloaded
  copies may need `xattr -dr com.apple.quarantine <app>`.
- **Windows:** needs a build on Windows; a code-signing cert avoids the SmartScreen
  warning (optional but recommended for distribution).

## Important: starting a fresh session (e.g. on Windows)

A new chat does NOT remember this conversation. To get back up to speed, tell the
assistant: **"Read HANDOFF.md and CLAUDE.md, then continue."** Everything needed is
in the repo (this file, CLAUDE.md = full spec, git history = what changed).
