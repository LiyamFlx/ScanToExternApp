# ScanToExternApp v5.0 — Build Phases 1–8 (macOS)

_Verbatim step-by-step build plan extracted from the original CLAUDE.md. Implement in this exact sequence. Phase 9 (Windows) lives in build-phases-windows.md._

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


