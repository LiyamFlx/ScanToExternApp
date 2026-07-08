# ScanToExternApp v5.0 — Build Rules

A cross-platform scan-to-text desktop app replacing Qt v4.1 with native Swift (macOS) + Rust/Tauri (Windows) + shared browser extension.

**Current state:** MAC PHASES 1–8 first (11 weeks), then Windows PHASE 9 (+5 weeks parallel from week 8).

## Core Rules

### Tech Stack — Non-Negotiable
- **Mac:** Swift 5.10+ + SwiftUI, AXUIElement injection, CoreBluetooth + IOKit, Sparkle 2
- **Windows:** Tauri 2.0 + Rust, Windows UI Automation, btleplug + serialport, Tauri updater
- **Web:** Chrome MV3 + Safari Web Extension (shared, identical on both platforms)
- **Storage:** SQLite (same schema both platforms), Keychain (Mac) / Credential Manager (Windows) for secrets
- **AI:** Apple Foundation Models (on-device, macOS 15.1+) + Claude API (opt-in, user key)

### Hard Constraints
- ❌ No Qt, no Electron, no monolithic codebase
- ❌ No app in Dock/Taskbar — menubar/tray only
- ❌ No VCP driver installation — use native APIs
- ❌ No world-writable files, no `chmod 777`, no secrets in config
- ❌ No cloud AI without explicit user opt-in per session
- ❌ WebSocket binds to `127.0.0.1` only, never `0.0.0.0`
- ✅ Injection fallback chain: native API → clipboard + keyboard
- ✅ AI processing gracefully degrades if network/model unavailable
- ✅ Settings use OS-native storage (`@AppStorage`, Keychain, Windows Credential Manager)

### Build Order (Strict)
1. **Phase 1:** Skeleton + Hardware (Bluetooth + USB)
2. **Phase 2:** Injection pipeline (AX + clipboard fallback)
3. **Phase 3:** Vision corrector + Preview toast
4. **Phase 4:** AI pipeline (Foundation Models + Claude API)
5. **Phase 5:** Scan history (GRDB + SQLite)
6. **Phase 6:** Browser extension (Chrome MV3 + Safari)
7. **Phase 7:** Settings + Permissions (Accessibility)
8. **Phase 8:** Auto-update + Packaging (Sparkle 2 + notarization/signing)
9. **Phase 9:** Windows Tauri app (parallel from week 8)

Test **each platform independently** before integration testing.

### Security Hardening
- API keys: Keychain (Mac) or Credential Manager (Windows), never UserDefaults/AppSettings
- File permissions: config/secrets `0600`, app bundle `0755`
- WebSocket messages: validated length (max 100KB), type allowlist
- Logging: no sensitive data (API keys, scan text) in release builds
- Code signing: Developer ID + notarization (Mac), EV cert + SmartScreen (Windows)
- Input validation: length limits on all user inputs, no eval/exec

### Acceptance Criteria
- **Sprint 1:** Menubar app, BLE + USB connect, AX injection into TextEdit, notarized
- **Sprint 2:** Preview toast, history, Chrome extension into Google Docs, Sparkle check
- **Sprint 3:** AI correction working, Safari extension, file permissions 0600, WebSocket localhost-only
- **Sprint 4 (Windows):** Tray app, UI Automation injection, MSI < 25MB signed, auto-update works

### When Starting Work
1. Read the relevant phase in `docs/claude/build-phases.md` (Mac) or `docs/claude/build-phases-windows.md` (Windows)
2. Refer to `docs/claude/architecture.md` for project structure and data flow
3. Check `docs/claude/constraints.md` for do/dont's and performance targets
4. Verify acceptance criteria in `docs/claude/acceptance-criteria.md`

**No pasting entire spec into each session** — reference `docs/claude/` files directly.

---

## Reference Docs

Quick index of external documentation files. Read as needed; they are NOT auto-loaded.

| File | Content | When to read |
|------|---------|--------------|
| `docs/claude/architecture.md` | Tech stack decisions (table form), project structure, data flow diagram, BLE protocol, Info.plist | Designing a new component; clarifying platform differences |
| `docs/claude/build-phases.md` | Week-by-week phases 1–8 (Mac), step-by-step code sketches for Swift components | Starting implementation of a phase; copying code patterns |
| `docs/claude/build-phases-windows.md` | Phase 9 (Windows), step-by-step code sketches for Rust/Tauri components | Starting Windows implementation; Rust reference |
| `docs/claude/constraints.md` | What NOT to build, file permissions, hardening, deployment limits, compatibility | Verifying no violations; checking security requirements; performance targets |
| `docs/claude/acceptance-criteria.md` | Sprint checklists, testing plan (unit + integration + E2E), security checklist, known limitations | Defining "done"; planning test cases; before shipping |

---

## Starter Commands

```bash
# 1. Create Xcode project manually first (File → New Project → macOS → App, see Phase 1)

# 2. Initialize git
git init && echo ".DS_Store\nbuild/\n*.xcuserdata" > .gitignore && git add . && git commit -m "init"

# 3. Add Package.swift dependencies (from build-phases.md, Phase 1.2)

# 4. Start with AppDelegate.swift and MenuBarController.swift (Phase 1.3)

# 5. Work through phases 1–8 in order, testing on real hardware before shipping
```

---

## Feedback for Future Sessions

If you've already worked on this, read `docs/claude/constraints.md` to avoid known pitfalls. If something isn't in the docs, it belongs there—suggest additions to keep this file under 8KB.

**Session link:** Paste this into Claude Code on every new session to load the rules. Do not re-paste the entire CLAUDE.md again; reference `docs/claude/` files instead.
