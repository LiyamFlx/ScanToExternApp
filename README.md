# ScanToExternApp v5.0

Native menubar app for Scanmarker pen scanners (macOS + Windows + shared browser extension).

See CLAUDE.md for the full master build prompt and phased implementation instructions.

## Current Status
- Phase 1 complete: Project skeleton + full menubar UI + Bluetooth (CoreBluetooth NUS) + USB serial (ORSSerialPort) + HardwareManager aggregation.
- Compiles cleanly via `swift build` in the `mac/` directory (as a library for logic validation).
- Full .app bundle with menubar, LSUIElement, permissions, AX etc. requires opening/creating an Xcode project.

## Quick Start (macOS)

**Detailed click-by-click instructions: [XCODE_SETUP.md](./XCODE_SETUP.md)**

### High-level summary
1. Create a new macOS → App project in Xcode (SwiftUI).
2. Drag the contents of `mac/ScanToExternApp/` into the project.
3. Add the 4 required SPM packages (GRDB.swift, SwiftyJSON/SwiftyJSON, Sparkle, ORSSerialPort).
4. Use the provided `Resources/Info.plist` (critical: LSUIElement = true, descriptions, no App Sandbox).
5. Disable App Sandbox + enable Hardened Runtime in the target.
6. Set deployment target to macOS 13.0.
7. Build & Run → pure menubar app.

### Test the full app instantly (no hardware/Scanmarker needed)
Right-click the menubar icon → **"Debug: Simulate Scan"**, or use the **"Test Scan"** button in the popover.

This exercises the complete pipeline:
- Configurable preview toast (edit + auto-inject after your timeout)
- Vision re-OCR
- AI (on-device or Claude if you entered a key in Settings)
- AX or clipboard injection into the focused app
- Save to History (searchable + re-inject works)

See XCODE_SETUP.md for the exact steps and troubleshooting.

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
