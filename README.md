# ScanToExternApp v5.0

Native menubar app for Scanmarker pen scanners (macOS + Windows + shared browser extension).

See CLAUDE.md for the full master build prompt and phased implementation instructions.

## Current Status
- Phase 1 complete: Project skeleton + full menubar UI + Bluetooth (CoreBluetooth NUS) + USB serial (ORSSerialPort) + HardwareManager aggregation.
- Compiles cleanly via `swift build` in the `mac/` directory (as a library for logic validation).
- Full .app bundle with menubar, LSUIElement, permissions, AX etc. requires opening/creating an Xcode project.

## Quick Start (macOS)

### 1. Open in Xcode (recommended)
1. Open Xcode.
2. File > New > Project > macOS > App.
3. Product Name: ScanToExternApp
4. Interface: SwiftUI, Language: Swift. Uncheck Core Data / tests / cloudkit for now.
5. Set Deployment Target: macOS 13.0
6. Bundle ID: com.topscan.ScanToExternApp
7. In the project:
   - Delete the default generated files (ContentView.swift etc) or keep App structure.
   - Drag or "Add Files" the contents of `mac/ScanToExternApp/` (App/, MenuBar/, Hardware/, etc.)
   - File > Add Packages... and add the four dependencies listed in `mac/Package.swift`:
     - GRDB.swift
     - SwiftyJSON/SwiftyJSON
     - sparkle-project/Sparkle
     - armadsen/ORSSerialPort
   - Copy or set the Info.plist from `mac/ScanToExternApp/Resources/Info.plist` into the target (or merge keys).
   - In Build Settings: enable Hardened Runtime.
   - In Signing & Capabilities: add the two usage descriptions if not in plist, and **disable** App Sandbox.
   - Set LSUIElement = YES (in plist).
   - Add a Run script phase or just build.
8. Build & Run. The app should appear only as a menubar icon (no Dock).

### 2. Alternative: use the SPM package for core validation
```bash
cd mac
swift build
```

### 3. After build in Xcode
- Grant Accessibility permission when prompted (for text injection).
- **Easiest testing (no hardware needed):** Right-click the menubar icon → "Debug: Simulate Scan", or click the "Test Scan" button in the popover.
  - This exercises the *full pipeline*: floating preview toast → optional Vision correction → AI processing (per Settings) → AXUIElement or clipboard fallback → history save.
- Real hardware: Plug Scanmarker USB or pair Bluetooth. The hardware layer receives UTF-8 text chunks (observe in Console).
- Preview toast: bottom-right, editable, auto-injects (or click Inject/Discard). Works for native apps + (via extension) web apps.

## Project Layout
See CLAUDE.md "Project Structure" section.

## Next Steps (per build order)
Follow CLAUDE.md exactly:
- Phase 2: Injection (AX + clipboard + WS bridge + router)
- Phase 3: VisionCorrector + Preview toast
- ... etc.

## Windows + Browser Extension
See CLAUDE.md for Tauri + BrowserExtension/ setup (later phases).

## Code Signing / Notarization
Developer ID: RBRX2Y72NR (update in your signing settings).
See Phase 8 for Sparkle + notarize commands.

## Hardware Notes
- BLE: Nordic UART Service (standard UUIDs listed in CLAUDE.md)
- USB: 115200 8N1 on Silicon Labs VCP

## Troubleshooting
- No BT device found? Use Bluetooth Explorer (Xcode additional tools) to sniff actual service UUIDs for your hardware revision.
- App shows in Dock? Ensure LSUIElement true + no other scenes/windows.
- Injection not working? Check Accessibility permission (System Settings > Privacy & Security).

## License / Distribution
Production quality, signed, notarized target.
