ScanToExternApp v5.0 — Master Build Prompt for Claude Code
How to use this: Paste the entire contents of this file as your opening message in a Claude Code session. Claude Code will use it as the project specification and build the application incrementally. Start each new session by running /init or referencing this file as CLAUDE.md in the project root.


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


Build Order — Implement in This Exact Sequence
Phase 1 — Skeleton + Hardware (Week 1–2)
Step 1.1 — Project bootstrap

mkdir ScanToExternApp && cd ScanToExternApp

# Create Xcode project: macOS App, SwiftUI, no Core Data, no tests yet

# Set deployment target: macOS 13.0

# Bundle ID: com.topscan.ScanToExternApp (keep existing for migration)

# Enable: Hardened Runtime, App Sandbox OFF (required for AXUIElement)

Step 1.2 — Package.swift dependencies

dependencies: [

    .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0"),

    .package(url: "https://github.com/nicklockwood/SwiftyJSON", from: "5.0.0"), // for Claude API

    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),

    // ORSSerialPort for USB serial (Silicon Labs VCP)

    .package(url: "https://github.com/armadsen/ORSSerialPort", from: "2.1.0"),

]

Step 1.3 — Menubar app skeleton

AppDelegate.swift:

NSStatusItem with a scanner icon (SF Symbol: doc.text.viewfinder)
Left click → show/hide SwiftUI popover
Right click → quit menu
App must NOT appear in Dock (LSUIElement = YES in Info.plist)

MenuBarView.swift (SwiftUI popover, 320×480pt):

Status indicator: Connected / Disconnected / Scanning
Last scanned text preview (last 80 chars, truncated)
Buttons: History, Settings, AI toggle
Device name + battery % when connected

Step 1.4 — Bluetooth manager

BluetoothManager.swift:

class BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    // Scan for Scanmarker devices by service UUID

    // Scanmarker BT service UUID: confirm from hardware docs or sniff with Bluetooth Explorer

    // Use UUID: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E" (Nordic UART Service — common for Scanmarker)

    // On connect: subscribe to RX characteristic for incoming OCR text

    // Parse incoming data: UTF-8 text chunks, reassemble to complete scan

    // Publish via Combine: PassthroughSubject<String, Never>

    // Handle reconnection with exponential backoff

}

Step 1.5 — USB serial manager

USBSerialManager.swift:

Use ORSSerialPort to find Silicon Labs VCP device (/dev/cu.SLAB_USBtoUART or similar)
Baud rate: 115200 (standard for Scanmarker USB)
Parse same text protocol as Bluetooth
Publish via same Combine subject as BluetoothManager

Step 1.6 — Hardware manager

HardwareManager.swift:

Aggregates BluetoothManager + USBSerialManager
Single @Published var lastScan: String?
Single @Published var connectionState: ConnectionState
Preference: Bluetooth over USB if both connected


Phase 2 — Injection Pipeline (Week 2–3)
Step 2.1 — AXUIElement injector

AXInjector.swift:

class AXInjector {

    func inject(_ text: String) -> Bool {

        // 1. Get frontmost app PID

        guard let app = NSWorkspace.shared.frontmostApplication else { return false }

        let pid = app.processIdentifier

        

        // 2. Get focused element

        let axApp = AXUIElementCreateApplication(pid)

        var focusedElement: AnyObject?

        AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard let element = focusedElement else { return false }

        

        // 3. Check if element is settable

        var settable: DarwinBoolean = false

        AXUIElementIsAttributeSettable(element as! AXUIElement, kAXValueAttribute as CFString, &settable)

        

        if settable.boolValue {

            // 4a. Get existing value and append/insert at cursor

            var currentValue: AnyObject?

            AXUIElementCopyAttributeValue(element as! AXUIElement, kAXValueAttribute as CFString, &currentValue)

            let existing = (currentValue as? String) ?? ""

            

            // Get selected range to find cursor position

            var selectedRange: AnyObject?

            AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &selectedRange)

            

            // Insert text at cursor position

            AXUIElementSetAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)

            return true

        }

        return false // fall through to clipboard injector

    }

    

    func requestAccessibilityPermission() {

        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]

        AXIsProcessTrustedWithOptions(options as CFDictionary)

    }

}

Step 2.2 — Clipboard injector (fallback)

ClipboardInjector.swift:

class ClipboardInjector {

    func inject(_ text: String) {

        // Save existing clipboard

        let previous = NSPasteboard.general.string(forType: .string)

        

        // Write text to clipboard

        NSPasteboard.general.clearContents()

        NSPasteboard.general.setString(text, forType: .string)

        

        // Post Cmd+V

        let source = CGEventSource(stateID: .hidSystemState)

        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)

        let vUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)

        vDown?.flags = .maskCommand

        vUp?.flags   = .maskCommand

        vDown?.post(tap: .cghidEventTap)

        vUp?.post(tap: .cghidEventTap)

        

        // Restore clipboard after 300ms

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {

            NSPasteboard.general.clearContents()

            if let prev = previous {

                NSPasteboard.general.setString(prev, forType: .string)

            }

        }

    }

}

Step 2.3 — WebSocket bridge

WebSocketBridge.swift:

// Local WebSocket server on ws://127.0.0.1:52731

// Protocol: JSON messages

// Message types:

//   { "type": "scan", "text": "...", "id": "uuid" }

//   { "type": "ack",  "id": "uuid" }

//   { "type": "ping" }

// Use Network.framework NWListener — no third-party dependency needed

// Only accept connections from 127.0.0.1 (localhost guard)

// Keep-alive ping every 10 seconds

// Broadcast incoming scan to all connected extension clients

Step 2.4 — Injection router

InjectionRouter.swift:

class InjectionRouter {

    let ax = AXInjector()

    let clipboard = ClipboardInjector()

    let bridge = WebSocketBridge()

    

    func route(_ text: String) {

        // Always broadcast to browser extension (for web apps)

        bridge.broadcast(text)

        

        // For native apps: try AX first, fallback to clipboard

        let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""

        let isBrowser = ["com.google.Chrome", "com.apple.Safari",

                         "org.mozilla.firefox", "com.microsoft.edgemac"].contains(frontApp)

        

        if !isBrowser {

            if !ax.inject(text) {

                clipboard.inject(text)

            }

        }

        // For browsers: extension handles injection via content script

    }

}


Phase 3 — Vision Corrector + Preview (Week 3)
Step 3.1 — Vision corrector

VisionCorrector.swift:

import Vision

class VisionCorrector {

    // Only called when hardware OCR confidence is below threshold

    // The Scanmarker sends text; we don't have the image

    // So: Vision corrector runs on a screen capture of the area being scanned

    // Implementation: take screenshot of region near cursor, run VNRecognizeTextRequest

    

    func correct(hardwareText: String, completion: @escaping (String) -> Void) {

        // Take screenshot of focused region

        // CGWindowListCreateImage for frontmost window

        let request = VNRecognizeTextRequest { request, error in

            guard let observations = request.results as? [VNRecognizedTextObservation] else {

                completion(hardwareText) // passthrough on failure

                return

            }

            let visionText = observations

                .compactMap { $0.topCandidates(1).first?.string }

                .joined(separator: " ")

            

            // Pick whichever has higher confidence

            // Simple heuristic: if vision text differs significantly, prefer longer one

            let result = visionText.count > hardwareText.count * 2 ? hardwareText : visionText

            completion(result)

        }

        request.recognitionLevel = .accurate

        request.usesLanguageCorrection = true

    }

}

Step 3.2 — Preview window

PreviewWindowController.swift:

Frameless floating window, NSBorderlessWindowMask
Appears bottom-right of screen, above all windows (NSFloatingWindowLevel)
Auto-dismisses after 2 seconds if no interaction
Shows scanned text (truncated to 120 chars)
Buttons: Inject (green, default), Edit, Discard
Edit: opens inline text field, user can correct before injecting
Keyboard: Return = inject, Escape = discard
Subtle slide-in animation

PreviewView.swift (SwiftUI):

struct PreviewView: View {

    @State var text: String

    @State var isEditing = false

    var onInject: (String) -> Void

    var onDiscard: () -> Void

    

    var body: some View {

        VStack(alignment: .leading, spacing: 8) {

            HStack {

                Image(systemName: "doc.text.viewfinder")

                    .foregroundColor(.blue)

                Text("Scanned Text")

                    .font(.caption).foregroundColor(.secondary)

                Spacer()

                // Auto-dismiss countdown timer visual

            }

            if isEditing {

                TextEditor(text: $text)

                    .frame(minHeight: 60)

            } else {

                Text(text)

                    .lineLimit(3)

                    .font(.body)

            }

            HStack {

                Button("Discard") { onDiscard() }

                    .foregroundColor(.red)

                Spacer()

                Button(isEditing ? "Edit" : "Edit") { isEditing.toggle() }

                Button("Inject") { onInject(text) }

                    .buttonStyle(.borderedProminent)

            }

        }

        .padding()

        .frame(width: 340)

        .background(.regularMaterial)

        .cornerRadius(12)

        .shadow(radius: 20)

    }

}


Phase 4 — AI Pipeline (Week 4)
Step 4.1 — Apple Foundation Models (on-device)

FoundationModelProcessor.swift:

// Requires: import FoundationModels (macOS 15.1+, Apple Intelligence enabled)

// Graceful fallback if not available

@available(macOS 15.1, *)

class FoundationModelProcessor {

    let session = LanguageModelSession()

    

    enum Mode {

        case correct       // Fix OCR errors, clean up spacing

        case translate(to: String)  // Translate to target language

        case summarize     // One-sentence summary

        case passthrough   // No processing

    }

    

    func process(_ text: String, mode: Mode) async throws -> String {

        let prompt: String

        switch mode {

        case .correct:

            prompt = "Fix any OCR errors, punctuation, and spacing in this scanned text. Return only the corrected text, nothing else:\n\n\(text)"

        case .translate(let lang):

            prompt = "Translate this text to \(lang). Return only the translation, nothing else:\n\n\(text)"

        case .summarize:

            prompt = "Summarize this in one sentence:\n\n\(text)"

        case .passthrough:

            return text

        }

        

        let response = try await session.respond(to: prompt)

        return response.content

    }

}

Step 4.2 — Claude API processor (opt-in)

ClaudeProcessor.swift:

// Endpoint: https://api.anthropic.com/v1/messages

// Model: claude-haiku-4-5 (fastest, cheapest for this use case)

// User must provide their API key in Settings

// All API calls are user-initiated (opt-in toggle in Settings)

struct ClaudeProcessor {

    var apiKey: String

    

    func process(_ text: String, instruction: String) async throws -> String {

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)

        request.httpMethod = "POST"

        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        

        let body: [String: Any] = [

            "model": "claude-haiku-4-5",

            "max_tokens": 1024,

            "messages": [

                ["role": "user", "content": "\(instruction)\n\n\(text)"]

            ]

        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        

        let (data, _) = try await URLSession.shared.data(for: request)

        // Parse response.content[0].text

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let content = ((json["content"] as! [[String:Any]]).first!["text"] as! String)

        return content

    }

}

Step 4.3 — AI processor orchestrator

AIProcessor.swift:

class AIProcessor: ObservableObject {

    @Published var mode: ProcessingMode = .off

    @Published var customInstruction: String = ""

    

    enum ProcessingMode: String, CaseIterable {

        case off = "Off"

        case correct = "Auto-correct OCR"

        case translate = "Translate"

        case summarize = "Summarize"

        case custom = "Custom instruction"

    }

    

    func process(_ text: String) async -> String {

        switch mode {

        case .off: return text

        case .correct:

            if #available(macOS 15.1, *) {

                return (try? await FoundationModelProcessor().process(text, mode: .correct)) ?? text

            }

            return text

        case .translate:

            let lang = SettingsStore.shared.targetLanguage

            if #available(macOS 15.1, *) {

                return (try? await FoundationModelProcessor().process(text, mode: .translate(to: lang))) ?? text

            }

            return text

        case .summarize, .custom:

            guard let key = SettingsStore.shared.claudeAPIKey, !key.isEmpty else { return text }

            let instruction = mode == .custom ? customInstruction : "Summarize in one sentence:"

            return (try? await ClaudeProcessor(apiKey: key).process(text, instruction: instruction)) ?? text

        }

    }

}


Phase 5 — Scan History (Week 4)
Step 5.1 — Database schema

ScanHistoryStore.swift:

import GRDB

struct ScanRecord: Codable, FetchableRecord, PersistableRecord {

    var id: String = UUID().uuidString

    var text: String

    var processedText: String?     // after AI processing

    var timestamp: Date

    var source: String             // "bluetooth" | "usb"

    var injectedTo: String?        // bundle ID of target app

    var aiMode: String?            // which AI mode was applied

    

    static let databaseTableName = "scan_records"

}

// Migration:

// CREATE TABLE scan_records (

//   id TEXT PRIMARY KEY,

//   text TEXT NOT NULL,

//   processed_text TEXT,

//   timestamp DATETIME NOT NULL,

//   source TEXT NOT NULL,

//   injected_to TEXT,

//   ai_mode TEXT

// )

// CREATE INDEX idx_timestamp ON scan_records(timestamp DESC)

class ScanHistoryStore {

    let db: DatabaseQueue

    

    init() {

        let path = FileManager.default

            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

            .appendingPathComponent("ScanToExternApp/history.sqlite")

        db = try! DatabaseQueue(path: path.path)

        try! migrate()

    }

    

    func save(_ record: ScanRecord) throws {

        try db.write { db in try record.save(db) }

    }

    

    func recent(limit: Int = 100) throws -> [ScanRecord] {

        try db.read { db in

            try ScanRecord

                .order(Column("timestamp").desc)

                .limit(limit)

                .fetchAll(db)

        }

    }

    

    func search(_ query: String) throws -> [ScanRecord] {

        try db.read { db in

            try ScanRecord

                .filter(Column("text").like("%\(query)%"))

                .order(Column("timestamp").desc)

                .fetchAll(db)

        }

    }

    

    func deleteAll() throws {

        try db.write { db in try ScanRecord.deleteAll(db) }

    }

}

Step 5.2 — History view

HistoryView.swift (SwiftUI panel, opens from menubar):

Search bar at top
List of scan records: timestamp, truncated text, target app icon
Tap a record → full text + re-inject button
Swipe to delete
"Clear All" button with confirmation
Export as plain text or CSV


Phase 6 — Browser Extension (Week 5–6)
Step 6.1 — Chrome MV3 manifest

manifest.json:

{

  "manifest_version": 3,

  "name": "ScanToExternApp",

  "version": "5.0.0",

  "description": "Injects Scanmarker pen scanner text into any web app",

  "permissions": ["activeTab", "scripting"],

  "host_permissions": ["<all_urls>"],

  "background": {

    "service_worker": "background.js"

  },

  "content_scripts": [{

    "matches": ["<all_urls>"],

    "js": ["content.js"],

    "run_at": "document_idle"

  }],

  "action": {

    "default_popup": "popup.html",

    "default_icon": "icon128.png"

  }

}

Step 6.2 — Background service worker

background.js:

let socket = null;

let reconnectTimer = null;

function connect() {

  socket = new WebSocket('ws://127.0.0.1:52731');

  

  socket.onopen = () => {

    console.log('ScanToExternApp: connected');

    clearTimeout(reconnectTimer);

  };

  

  socket.onmessage = async (event) => {

    const msg = JSON.parse(event.data);

    if (msg.type === 'scan') {

      // Send to active tab's content script

      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });

      if (tab?.id) {

        chrome.tabs.sendMessage(tab.id, { type: 'inject', text: msg.text, id: msg.id });

      }

      // ACK back to app

      socket.send(JSON.stringify({ type: 'ack', id: msg.id }));

    }

  };

  

  socket.onclose = () => {

    reconnectTimer = setTimeout(connect, 3000); // reconnect every 3s

  };

  

  socket.onerror = () => socket.close();

}

connect();

Step 6.3 — Content script

content.js:

chrome.runtime.onMessage.addListener((msg) => {

  if (msg.type !== 'inject') return;

  

  const el = document.activeElement;

  if (!el) return;

  

  // Strategy 1: Standard input/textarea

  if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {

    const start = el.selectionStart ?? el.value.length;

    const end   = el.selectionEnd   ?? el.value.length;

    el.value = el.value.slice(0, start) + msg.text + el.value.slice(end);

    el.selectionStart = el.selectionEnd = start + msg.text.length;

    el.dispatchEvent(new Event('input', { bubbles: true }));

    el.dispatchEvent(new Event('change', { bubbles: true }));

    return;

  }

  

  // Strategy 2: contenteditable (Google Docs, Notion, etc.)

  if (el.isContentEditable || el.closest('[contenteditable]')) {

    document.execCommand('insertText', false, msg.text);

    return;

  }

  

  // Strategy 3: Google Docs specific (uses a hidden textarea)

  const gdocsEditor = document.querySelector('.docs-texteventtarget-iframe');

  if (gdocsEditor) {

    gdocsEditor.contentDocument?.execCommand('insertText', false, msg.text);

    return;

  }

  

  // Strategy 4: Clipboard fallback (last resort)

  navigator.clipboard.writeText(msg.text).then(() => {

    document.execCommand('paste');

  });

});

Step 6.4 — Extension popup

popup.html / popup.js:

Show connection status: green dot if WebSocket connected, red if not
Last scanned text preview
Toggle: "Auto-inject" on/off
Link: "Open ScanToExternApp" (custom URL scheme back to native app)
Instruction: "Open the ScanToExternApp menubar icon to configure"

Step 6.5 — Safari Web Extension

Create Xcode project: File → New → Project → Safari Extension
Import the same background.js, content.js, popup.html
Safari Web Extensions use the same MV3 API with minor differences
Bundle as part of the main macOS app (appears in Safari Extensions preferences automatically)


Phase 7 — Settings + Permissions (Week 6)
Step 7.1 — Settings store

SettingsStore.swift:

class SettingsStore: ObservableObject {

    static let shared = SettingsStore()

    

    @AppStorage("previewEnabled")    var previewEnabled: Bool   = true

    @AppStorage("previewTimeout")    var previewTimeout: Double = 2.0  // seconds

    @AppStorage("aiMode")            var aiMode: String         = "off"

    @AppStorage("targetLanguage")    var targetLanguage: String = "English"

    @AppStorage("claudeAPIKey")      var claudeAPIKey: String   = ""

    @AppStorage("historyEnabled")    var historyEnabled: Bool   = true

    @AppStorage("historyLimit")      var historyLimit: Int      = 500

    @AppStorage("preferBluetooth")   var preferBluetooth: Bool  = true

    @AppStorage("launchAtLogin")     var launchAtLogin: Bool    = true

    @AppStorage("injectionMethod")   var injectionMethod: String = "ax" // "ax" | "clipboard"

}

Step 7.2 — Permissions manager

PermissionsManager.swift:

class PermissionsManager: ObservableObject {

    @Published var hasAccessibility = false

    @Published var hasBluetooth     = false

    

    func checkAll() {

        hasAccessibility = AXIsProcessTrusted()

        // Bluetooth state determined by CBCentralManager

    }

    

    func requestAccessibility() {

        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]

        AXIsProcessTrustedWithOptions(opts as CFDictionary)

        // Poll every 1s for 10s to detect grant

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in

            if AXIsProcessTrusted() {

                self?.hasAccessibility = true

                t.invalidate()

            }

        }

    }

    

    // Show onboarding checklist on first launch:

    // ☐ Grant Accessibility permission

    // ☐ Connect your Scanmarker (Bluetooth or USB)

    // ☐ Install browser extension (optional, for Google Docs / web apps)

}

Step 7.3 — Settings view

SettingsView.swift (SwiftUI, opens as a separate window):

General tab: Launch at login, preview timeout, injection method
AI tab: Mode selector, target language, Claude API key field (password style)
History tab: Enable/disable, limit, clear all
Device tab: Connected device name, signal strength, prefer BT/USB
Extension tab: Install status indicator, link to Chrome Web Store / Safari Extensions


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


Phase 8 — Auto-update + Packaging (Week 7)
Step 8.1 — Sparkle 2

// AppDelegate.swift

import Sparkle

let updaterController = SPUStandardUpdaterController(

    startingUpdater: true,

    updaterDelegate: nil,

    userDriverDelegate: nil

)

// Info.plist:

// SUFeedURL = https://your-update-server.com/appcast.xml

// SUPublicEDKey = <your EdDSA public key from generate_keys>

Step 8.2 — Build & sign

# Build

xcodebuild -scheme ScanToExternApp -configuration Release archive \

  -archivePath build/ScanToExternApp.xcarchive

# Export

xcodebuild -exportArchive \

  -archivePath build/ScanToExternApp.xcarchive \

  -exportPath build/export \

  -exportOptionsPlist ExportOptions.plist  # method: developer-id

# Notarize

xcrun notarytool submit build/export/ScanToExternApp.dmg \

  --apple-id "your@email.com" \

  --team-id RBRX2Y72NR \

  --password "@keychain:AC_PASSWORD" \

  --wait

# Staple

xcrun stapler staple build/export/ScanToExternApp.dmg

Step 8.3 — DMG layout

Target size: <25 MB
Contents: ScanToExternApp.app + Applications symlink
Background image with arrow
No .pkg. No pre/post install scripts. No VCP driver (handled by CoreBluetooth + IOKit natively)


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


Acceptance Criteria (Definition of Done)
Sprint 1 complete when:
App launches as menubar icon, no Dock icon
Scanmarker connects over Bluetooth — connection status shows in menubar popover
Scanmarker connects over USB — same
Scanning text injects into TextEdit via AXUIElement
Scanning text injects via clipboard into apps that block AX API
App is notarized and opens without Gatekeeper warning
Install size < 30 MB
Sprint 2 complete when:
Preview toast appears for every scan, dismisses after 2s
User can edit text in preview before injecting
Discard button works
Scan history shows last 100 scans with search
Re-inject from history works
Chrome extension installed → text injects into Google Docs correctly
Chrome extension shows green connected status when app is running
Sparkle update check works
Sprint 3 complete when:
AI correction improves Scanmarker misreads (test with 10 known bad scans)
Translation to Spanish/French/German works on-device (macOS 15+)
Claude API mode works with user-provided key (test with summarize)
Safari extension injects into Google Docs in Safari
All license files are 0600
WebSocket only binds to 127.0.0.1
Sprint 4 (Windows) complete when:
Tauri tray app launches on Windows 10/11, no Dock/taskbar icon
Scanmarker connects over Bluetooth on Windows — tray shows Connected
Scanmarker connects over USB (COM port) on Windows — same
Scanning text injects into Notepad via Windows UI Automation
Scanning text injects into desktop Word via Windows UI Automation
Scanning text injects into Outlook desktop via Windows UI Automation
Clipboard fallback works when UIA fails
Chrome extension on Windows shows green connected status when Tauri app running
Chrome extension injects into Google Docs on Windows correctly
Preview toast appears bottom-right on Windows, same UX as Mac
Scan history works on Windows (SQLite, same schema)
MSI installer is < 25 MB, signed, passes Windows SmartScreen
Auto-update works via Tauri updater
Same Claude API key works on Windows (stored in Windows Credential Manager)


Testing Plan
// Tests/InjectionTests/AXInjectorTests.swift

// - Open TextEdit, inject "Hello World", assert text appears

// - Open Safari address bar, inject URL, assert it appears

// - Test fallback when AX permission denied

// Tests/OCRTests/VisionCorrectorTests.swift

// - Feed known misread strings, assert correction improves them

// Tests/HistoryTests/ScanHistoryStoreTests.swift

// - Save 10 records, fetch recent(limit: 5), assert 5 returned

// - Search "test", assert only matching records returned

// - deleteAll(), assert empty


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


Reference: Scanmarker BLE Protocol
The Scanmarker Air uses Nordic UART Service (NUS) over BLE:

Service UUID: 6E400001-B5A3-F393-E0A9-E50E24DCCA9E
TX Characteristic (scanner → app): 6E400003-B5A3-F393-E0A9-E50E24DCCA9E
RX Characteristic (app → scanner): 6E400002-B5A3-F393-E0A9-E50E24DCCA9E
Data format: Raw UTF-8 bytes, chunked at 20 bytes per BLE packet
Reassembly: Buffer chunks until 300ms of silence, then emit complete string
USB baud rate: 115200, 8N1

If UUIDs don't match on your specific hardware revision, use Bluetooth Explorer (Xcode dev tools) to sniff the actual service/characteristic UUIDs while scanning.


Starter Commands for Claude Code
# 1. Create Xcode project (do this manually in Xcode first, then continue here)

# File → New Project → macOS → App

# Product Name: ScanToExternApp

# Bundle Identifier: com.topscan.ScanToExternApp

# Interface: SwiftUI

# Language: Swift

# Uncheck: Include Tests (add manually), Core Data, CloudKit

# 2. Initialize git

git init && echo ".DS_Store\nbuild/\n*.xcuserdata" > .gitignore && git add . && git commit -m "init"

# 3. Add Package.swift dependencies (SPM)

# Open Package.swift and add the dependencies listed in Phase 1 above

# 4. Start with AppDelegate.swift and MenuBarController.swift

# Then work through phases 1–8 in order


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


