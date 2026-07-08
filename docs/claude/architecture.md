# ScanToExternApp v5.0 — Architecture Reference

_Verbatim reference material extracted from the original CLAUDE.md build prompt. Not auto-loaded; read when designing components or clarifying platform decisions._

Project Overview
You are building ScanToExternApp v5.0 — a next-generation scan-to-text desktop companion for Scanmarker pen scanner hardware that works on both macOS and Windows. The existing app (v4.1.0.0) is a 938 MB Qt/WebEngine monolith, macOS only. You are replacing it entirely with:

A native Swift menubar app for macOS (~15 MB target)
A Tauri 2.0 system tray app for Windows (~10 MB target)
A Chrome + Safari browser extension shared across both platforms

The core user flow is identical on both platforms:

User scans printed text with the Scanmarker pen → app receives OCR'd text from hardware → user sees a 1-second preview → text injects into the focused window (Word, Notepad, Notes, email, Google Docs, browser, social media — ANY focused text field on the OS)

Platform coverage:

Target
Mac
Windows
Native apps (Word desktop, Notepad, Mail)
✅ Swift + AXUIElement
✅ Tauri + Windows UI Automation
Browser apps (Google Docs, Gmail, Twitter)
✅ Browser extension
✅ Same browser extension
Clipboard fallback
✅ NSPasteboard + Cmd+V
✅ Windows clipboard + Ctrl+V


This must be production-quality, signed, notarized (Mac) / signed (Windows), and shippable on both platforms.


Hard Technical Decisions (non-negotiable)
macOS
Decision
Choice
Reason
Language
Swift 5.10+
Native macOS, AXUIElement access, CoreBluetooth
UI framework
SwiftUI + AppKit where needed
Menubar app doesn't need UIKit
Primary injection
AXUIElement (C API via Swift)
Direct, no clipboard pollution
Fallback injection
NSPasteboard + CGEventPost Cmd+V
Universal compatibility
Secondary OCR
Apple Vision Framework (VNRecognizeTextRequest)
On-device, free, private
AI on-device
Apple Foundation Models (macOS 15.1+)
Zero latency, zero cost, private
AI cloud (opt-in)
Anthropic Claude API (claude-haiku-4-5)
Best quality, user-toggled
Local storage
SQLite via GRDB.swift
Scan history, settings
Hardware - BT
CoreBluetooth
Native BT LE HID
Hardware - USB
IOKit + ORSSerialPort
Silicon Labs VCP replacement
Browser bridge
Local WebSocket server on 127.0.0.1:52731
Extension ↔ app IPC
Browser extension
Chrome MV3 + Safari Web Extension
Cross-browser
Auto-update
Sparkle 2
Delta updates, no pkg reinstall
Package manager
Swift Package Manager
No CocoaPods
Min macOS
macOS 13.0 (Ventura)
SwiftUI stability
Code signing
Developer ID (existing: RBRX2Y72NR)
Notarization required

Windows
Decision
Choice
Reason
Framework
Tauri 2.0
Rust backend + web frontend, ~10 MB, native tray support
Backend language
Rust
Memory-safe, tiny binary, excellent Windows API access
Frontend UI
HTML/CSS/JS (shared with browser extension popup)
Reuse existing UI code
Primary injection
Windows UI Automation API (uiautomation Rust crate)
Equivalent of AXUIElement — injects into Word, Notepad, Outlook, any native app
Fallback injection
enigo Rust crate (clipboard + Ctrl+V simulation)
Universal Windows fallback
Hardware - BT
btleplug Rust crate
Cross-platform BLE, same Nordic UART UUIDs
Hardware - USB
serialport Rust crate
COM port access for Silicon Labs VCP
Browser bridge
Same WebSocket on 127.0.0.1:52731
Identical protocol — same browser extension works on both platforms
Local storage
SQLite via rusqlite crate
Same schema as Mac
AI cloud (opt-in)
Claude API via reqwest Rust crate
Same user API key as Mac
Auto-update
Tauri built-in updater
Signed MSI delta updates
Min Windows
Windows 10 (1903+)
UI Automation stable
Code signing
EV Code Signing Certificate (Sectigo / DigiCert)
Required to pass Windows SmartScreen
Installer
NSIS or MSI via Tauri bundler
Small, no reboot required



Project Structure
ScanToExternApp/

├── CLAUDE.md                              ← this file (paste here)

│

├── mac/                                   ← macOS Swift app (Xcode project)

│   ├── Package.swift                      ← SPM manifest

│   ├── ScanToExternApp/

│   │   ├── App/

│   │   │   ├── ScanToExternAppApp.swift   ← @main, NSApplicationDelegate

│   │   │   └── AppDelegate.swift

│   │   ├── MenuBar/

│   │   │   ├── MenuBarController.swift    ← NSStatusItem, popover

│   │   │   └── MenuBarView.swift          ← SwiftUI popover content

│   │   ├── Hardware/

│   │   │   ├── HardwareManager.swift      ← Coordinates BT + USB

│   │   │   ├── BluetoothManager.swift     ← CoreBluetooth CBCentralManager

│   │   │   └── USBSerialManager.swift     ← ORSSerialPort wrapper

│   │   ├── Injection/

│   │   │   ├── InjectionRouter.swift      ← Decides which injector to use

│   │   │   ├── AXInjector.swift           ← AXUIElement primary injector

│   │   │   ├── ClipboardInjector.swift    ← NSPasteboard + CGEventPost fallback

│   │   │   └── WebSocketBridge.swift      ← Broadcasts to browser extension

│   │   ├── OCR/

│   │   │   └── VisionCorrector.swift      ← Apple Vision re-reads if confidence < 0.85

│   │   ├── AI/

│   │   │   ├── AIProcessor.swift          ← Orchestrates on-device + cloud

│   │   │   ├── FoundationModelProcessor.swift  ← Apple Foundation Models

│   │   │   └── ClaudeProcessor.swift      ← Anthropic API (opt-in)

│   │   ├── Preview/

│   │   │   ├── PreviewWindowController.swift   ← Floating toast window

│   │   │   └── PreviewView.swift

│   │   ├── History/

│   │   │   ├── ScanHistoryStore.swift     ← GRDB SQLite wrapper

│   │   │   ├── ScanRecord.swift

│   │   │   └── HistoryView.swift

│   │   ├── Settings/

│   │   │   ├── SettingsStore.swift

│   │   │   └── SettingsView.swift

│   │   ├── Permissions/

│   │   │   └── PermissionsManager.swift

│   │   └── Resources/

│   │       ├── Assets.xcassets

│   │       └── Info.plist

│   └── Tests/

│

├── windows/                               ← Windows Tauri 2.0 app

│   ├── src-tauri/                         ← Rust backend

│   │   ├── Cargo.toml

│   │   ├── tauri.conf.json

│   │   └── src/

│   │       ├── main.rs                    ← Tauri app entry, tray setup

│   │       ├── hardware/

│   │       │   ├── mod.rs

│   │       │   ├── bluetooth.rs           ← btleplug BLE manager

│   │       │   └── usb_serial.rs          ← serialport COM manager

│   │       ├── injection/

│   │       │   ├── mod.rs

│   │       │   ├── uia_injector.rs        ← Windows UI Automation primary

│   │       │   ├── clipboard_injector.rs  ← enigo Ctrl+V fallback

│   │       │   └── websocket_bridge.rs    ← tokio-tungstenite WS server

│   │       ├── ai/

│   │       │   └── claude_processor.rs    ← reqwest Claude API calls

│   │       ├── history/

│   │       │   └── store.rs               ← rusqlite scan history

│   │       └── preview/

│   │           └── preview_window.rs      ← Tauri window for preview toast

│   └── src/                               ← Web frontend (shared with extension)

│       ├── index.html                     ← Tray popover UI

│       ├── popup.js                       ← Reuse from BrowserExtension/popup.js

│       └── styles.css

│

├── BrowserExtension/                      ← Shared across Mac + Windows

│   ├── manifest.json                      ← Chrome MV3 manifest

│   ├── background.js                      ← Service worker, WebSocket client

│   ├── content.js                         ← DOM text injection

│   ├── popup.html / popup.js              ← Extension popup UI

│   └── safari/                            ← Safari Web Extension (Xcode project)

│

└── shared/                                ← Shared assets + protocol spec

    ├── websocket-protocol.md              ← JSON message format (source of truth)

    ├── icons/                             ← App icons for both platforms

    └── scan-record-schema.sql             ← SQLite schema used by both platforms



Full Scan Pipeline — Data Flow
The pipeline is identical on both platforms. Only the injection layer differs.

Scanmarker hardware (BLE / USB serial — UTF-8 text chunks)

        │

        ▼

┌──────────────────────┬──────────────────────────┐

│  MAC                 │  WINDOWS                 │

│  HardwareManager     │  hardware::bluetooth +   │

│  (Swift/Combine)     │  usb_serial (Rust/tokio) │

└──────────┬───────────┴──────────────┬───────────┘

           │                          │

           └────────────┬─────────────┘

                        ▼

             VisionCorrector / OCR fix

             (Mac: Apple Vision · Windows: skip / Claude API)

                        │

                        ▼

             AIProcessor.process()

             (on-device or Claude API, per user setting)

                        │

                        ▼

             Preview toast — user sees text 2 seconds

                        │

              ┌─────────┴──────────┐

           Inject               Discard

              │

              ▼

   InjectionRouter / injection::mod.rs

              │

              ├──▶ WebSocketBridge (127.0.0.1:52731)

              │         └──▶ Browser extension content.js

              │              (Google Docs, Gmail, Twitter — ALL browsers, Mac + Windows)

              │

              ├──▶ [MAC]  AXInjector (AXUIElement)

              │           └──(fail)──▶ ClipboardInjector (NSPasteboard + Cmd+V)

              │

              └──▶ [WIN]  UiaInjector (Windows UI Automation)

                          └──(fail)──▶ ClipboardInjector (enigo + Ctrl+V)

              │

              ▼

   ScanHistoryStore.save() — SQLite, same schema both platforms


Info.plist Requirements
<!-- Required entitlements -->

<key>LSUIElement</key><true/>                    <!-- Hide from Dock -->

<key>NSBluetoothAlwaysUsageDescription</key>

<string>ScanToExternApp needs Bluetooth to connect to your Scanmarker scanner.</string>

<key>NSAccessibilityUsageDescription</key>

<string>ScanToExternApp needs Accessibility access to inject text into other apps.</string>

<!-- Disable App Sandbox (required for AXUIElement + CGEventPost) -->

<!-- Do NOT enable com.apple.security.app-sandbox -->

<!-- Hardened Runtime exceptions needed: -->

<key>com.apple.security.automation.apple-events</key><true/>


Security Hardening Checklist
WebSocket server binds to 127.0.0.1 only, never 0.0.0.0
WebSocket messages validated: max text length 100,000 chars, type allowlist
Claude API key stored in Keychain (not UserDefaults): use Security.framework SecKeychainItem
scan2extern:// URL scheme validates caller (check if message comes from own process)
License file permissions: 0600 (owner read/write only) — not 777
No world-writable files anywhere
App Transport Security enabled (HTTPS only for Claude API)
Sparkle uses EdDSA signatures (not DSA)


Reference: Scanmarker BLE Protocol
The Scanmarker Air uses Nordic UART Service (NUS) over BLE:

Service UUID: 6E400001-B5A3-F393-E0A9-E50E24DCCA9E
TX Characteristic (scanner → app): 6E400003-B5A3-F393-E0A9-E50E24DCCA9E
RX Characteristic (app → scanner): 6E400002-B5A3-F393-E0A9-E50E24DCCA9E
Data format: Raw UTF-8 bytes, chunked at 20 bytes per BLE packet
Reassembly: Buffer chunks until 300ms of silence, then emit complete string
USB baud rate: 115200, 8N1

If UUIDs don't match on your specific hardware revision, use Bluetooth Explorer (Xcode dev tools) to sniff the actual service/characteristic UUIDs while scanning.



Platform Support Summary
Feature
Mac
Windows
Tray / Menubar app
✅ Swift + SwiftUI
✅ Tauri 2.0 + Rust
Inject → Word (desktop)
✅ AXUIElement
✅ Windows UI Automation
Inject → Notepad / Notes
✅ AXUIElement
✅ Windows UI Automation
Inject → Outlook (desktop)
✅ AXUIElement
✅ Windows UI Automation
Inject → Google Docs
✅ Browser extension
✅ Same browser extension
Inject → Gmail / web email
✅ Browser extension
✅ Same browser extension
Inject → Twitter / social
✅ Browser extension
✅ Same browser extension
Bluetooth (Scanmarker Air)
✅ CoreBluetooth
✅ btleplug
USB (Scanmarker USB)
✅ IOKit + ORSSerialPort
✅ serialport crate
Preview toast
✅ SwiftUI window
✅ Tauri window
Scan history
✅ GRDB + SQLite
✅ rusqlite + SQLite
AI correction (on-device)
✅ Apple Foundation Models
⚠️ Claude API only (no on-device LLM on Windows)
AI translation / summarize
✅ Foundation Models + Claude
✅ Claude API
Auto-update
✅ Sparkle 2
✅ Tauri updater
Install size
~15 MB DMG
~10 MB MSI
Min OS
macOS 13.0
Windows 10 (1903+)




This prompt was generated from the ScanToExternApp v5.0 Strategic Analysis document. Mac phases 1–8 first, then Windows phase 9. Test each platform independently before integration testing. The goal is a shippable cross-platform v5.0 in ~16 weeks (Mac: 11 weeks · Windows: +5 weeks parallel from week 8).


---

## Original build-prompt header (preserved verbatim)

_The following was the opening of the monolithic CLAUDE.md before it was split. Kept here for provenance; the current workflow references docs/claude/ files instead of pasting the whole spec._

ScanToExternApp v5.0 — Master Build Prompt for Claude Code
How to use this: Paste the entire contents of this file as your opening message in a Claude Code session. Claude Code will use it as the project specification and build the application incrementally. Start each new session by running /init or referencing this file as CLAUDE.md in the project root.
