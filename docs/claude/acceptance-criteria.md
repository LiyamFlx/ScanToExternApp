# ScanToExternApp v5.0 — Acceptance Criteria & Testing Plan

_Verbatim Definition-of-Done and test plan extracted from the original CLAUDE.md._

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


