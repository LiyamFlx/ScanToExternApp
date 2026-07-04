# STATUS

Update at end of every session — source of truth, not memory/chat history.
Legend: ✅ verified working · 🟡 builds/exists but unverified · 🔄 in progress · ❌ broken/failing · ⬜ not started · 🚫 blocked (external dependency)

---

## MAC — `mac/`

### Build
- ✅ Clean local build (`xcodegen generate` + `xcodebuild`) — **verified this session**, `BUILD SUCCEEDED`, no errors.
- ✅ CI build — passing (run 28695377642, 2026-07-04).
- ✅ App launches, no Dock icon (`LSUIElement=true` confirmed baked into built Info.plist), status item registers, no crash on startup.

### Core pipeline — VERIFIED THIS SESSION (live, not just CI)
- ✅ **AX injection**: `SCANAPP_SELFTEST=1` opened real TextEdit, injected via `AXUIElement`, AX readback confirmed text landed. PASS.
- ✅ **Clipboard fallback injection**: same self-test, Cmd+V path, readback confirmed. PASS.
- ✅ **Full pipeline test** (`SCANAPP_PIPELINE_TEST=1`, 6 stages) — all PASS after Accessibility was (re)granted:
  - Inject (direct route) ✅
  - History persistence (SQLite) ✅
  - Device registry alive ✅
  - Empty-scan guard ✅
  - Preview→auto-inject→history flow ✅
  - Popover opens programmatically ✅
- ✅ Menubar popover UI driven live via clicks: status/connect section, History panel (real SQLite rows, search, Re-inject, Clear All), Settings panel (General tab: preview toggle, timeout slider, Launch-at-Login via `SMAppService` confirmed registered, injection method picker), all render and respond correctly.
- ✅ Self-test/pipeline-test menu items + env-var hooks exist and work — good headless verification infrastructure, keep using it.

### Known issues (found this session, not yet fixed)
- ❌ **Accessibility grant does not survive rebuilds.** Ad-hoc/self-signed cdhash changes on every build; TCC silently revokes trust even though bundle ID and `TCC.db` entry (`com.topscan.ScanToExternApp|2`) look unchanged. `AXIsProcessTrusted()` returns `false` after any rebuild until the user manually re-grants in System Settings. Reproduced live: first pipeline-test run failed Stage A/E for exactly this reason, second run passed after manual re-grant. Root-caused and documented in HANDOFF.md already — real fix is Developer ID signing with a stable designated requirement (see Notarization below).
- ⚠️ **Phantom BLE "Connected" state on cold launch.** With no physical Scanmarker pen present, the popover showed "✓ Connected: PenScanBLE5968CA" (green dot) on a fresh relaunch. Either `BluetoothManager`/`DeviceRegistry` isn't clearing persisted connection state on restart, or an unrelated nearby BLE peripheral is being misidentified as a paired Scanmarker. Needs investigation before the real-pen test session — could mask genuine pairing bugs or give false confidence.
- ⚠️ Popover's own "self-test" play button, when clicked while the popover itself is frontmost, injects into itself (`Sent 91 chars to ScanToExternApp`) instead of a real external target — confusing but not a functional bug; only meaningful with another app focused first.
- ⚠️ Scan History already contains leftover garbage-looking strings from earlier dev/fuzz sessions (`lkj"$#`, `xf`, `E8`) — harmless but should "Clear All" before any demo.
- ⚠️ Pipeline-test log line "history rows after: N" is capped at 5 by implementation (`recent(limit: 5)`), so it visually looks like data loss run-over-run — cosmetic log wording issue only, not a real bug (pass/fail is by content match, not count).

### Not yet done / untested
- 🚫 **Notarization** — blocked on Apple Developer Program enrollment ($99/yr). DMG currently only self-signed.
- ⬜ **Real Scanmarker pen over BLE** — never tested with actual hardware, only `simulateScan()`/debug injection. This is the biggest real gap: the entire BLE parsing/reassembly path (`BluetoothManager`, Nordic UART UUIDs, 300ms silence-based chunk reassembly) is unverified against a real device.
- ⬜ USB serial path (ORSSerialPort, Silicon Labs VCP) — unverified, no real hardware test.
- ⬜ Vision Corrector (Apple Vision fallback OCR) — not exercised this session.
- ⬜ AI pipeline (Foundation Models / Claude API) — not exercised this session; AI mode was forced "off" for pipeline test determinism.
- ⬜ Browser extension (Chrome/Safari) ↔ WebSocket bridge — bridge starts and listens on 127.0.0.1:52731 per logs, but no extension-side injection into Google Docs/Gmail was tested this session.
- ⬜ Safari Web Extension packaging — exists per CLAUDE.md structure, not verified.

---

## WINDOWS — `windows/`

Nothing below is independently verified by me this session — this is CI + static-analysis level confidence only, carried over from prior session notes. Treat accordingly.

### Build
- ✅ CI build — passing (run 28711940122, 2026-07-04, includes this session's BLE/OCR rewrite — **real Windows-target build succeeded, not just macOS-host `cargo check`**, 0 warnings/errors in the changed files per build log).
- 🟡 Installers generated by CI: `.msi` and NSIS `.exe`, confirmed present in prior runs — still never installed or run on a real machine this session.
- ⬜ Never built or run on an actual Windows machine — only cross-compiled/CI-built.

### Core pipeline — UNVERIFIED (except where noted)
- 🟡 UIA injection (`uia_injector.rs`): `ValuePattern` implemented for standard inputs. `TextPattern`/`ITextRangeProvider` write path was attempted and removed (API doesn't support insert) — rich-text controls (Word body, RichTextBox) fall through to clipboard+Ctrl-V by design, not a bug. Neither path has been exercised against a real Windows app.
- ✅ **BLE protocol fixed and now confirmed building on the real Windows CI target (run 28711940122).** `windows/src-tauri/src/hardware/bluetooth.rs` was rewritten: replaced the wrong Nordic-UART assumption (`6E400001-...`) with the real vendor GATT (`7c6b5200-a002-b001-c00X-...`, matching Mac's `BluetoothManager.swift` and an independent working TS/Web Bluetooth reference), added byte-accurate `DATA_START`/`DATA_END` stroke framing (`find_stroke`/`extract_air_payload`, ported from Mac's `indexOf(sequence:)`/`recognizeStroke`), added the vendor activation write sequence (0x0A/0x22), added BLE serial-number read (0x2A25) and battery read (0x2A19) with battery notifications no longer misrouted into the stroke buffer, and replaced `String::from_utf8_lossy` decode with a POST to the new OCR client. Passed `cargo check` locally (macOS host) and now the actual `cfg(windows)` CI build — still not run against real hardware or a live Windows Bluetooth stack.
- ✅ **Cloud-OCR client added: `windows/src-tauri/src/ai/run_ocr_client.rs`, confirmed building in the same Windows CI run.** Rust port of Mac's `RunOCRClient.swift` — same SOAP envelope, same field order/naming, same email+serial gating behavior, hand-rolled base64 (no new crate dependency; `reqwest` was already present for Claude). Added `AppSettings.scanmarker_email` / `scanmarker_language_id` (mirroring Mac's `SettingsStore.scanmarkerEmail`/`scanmarkerLanguageId`), defaulted to `liyam@scanmarker.com` on both platforms so OCR has a usable identity out of the box.
- ✅ **Settings UI gap closed — Scanmarker account email + local password gate, confirmed building on real Windows CI (run 28718397397).** `windows/src/settings.html` AI tab now has an email field and an optional local password; password is SHA-256 hashed via `credential_store.rs` (same Credential Manager backing as the Claude API key) and gates re-editing the email once set, mirroring Mac's `KeychainManager`/`ScanmarkerAccountWindowController` onboarding added this session. Not real auth — same as Mac, just a local "confirm it's you" check, no server, no verification.
- ⬜ Clipboard/Ctrl-V fallback (enigo/arboard) — implemented, never run.
- ⚠️ **USB serial has the same class of bug, not yet fixed.** `usb_serial.rs` still assumes "same text protocol as Bluetooth" and will hit the same UTF-8-decode-of-image-bytes problem if a Scanmarker Air is ever used over USB rather than BLE. No reference implementation for the USB framing was available this session — flagging as a follow-up rather than guessing at a fix.
- ⬜ WebSocket bridge (tokio-tungstenite, 127.0.0.1:52731, same protocol as Mac) — implemented, never run.
- ⬜ SQLite history (rusqlite) — implemented, never run.
- ⬜ System tray UI (Tauri) — implemented, never visually verified running.
- ⬜ Preview toast window — implemented per spec, never seen rendered.
- ⬜ Claude API integration — implemented, never exercised.

> **Status change from last entry:** BLE/OCR protocol was previously "actively wrong" (would silently connect and emit mojibake). Now: fixed in code, verified against a trusted reference implementation, and **confirmed compiling on the real Windows CI target** (not just macOS-host type-checking). Still zero hardware confirmation — treat as "correct on paper and provably compiles for Windows," not "known to work."

### Not yet done
- 🚫 EV Code Signing Certificate — not acquired; installer is unsigned, will trigger Windows SmartScreen warnings.
- ⬜ Tauri auto-updater — configured in principle per CLAUDE.md, not verified wired up or tested.
- ⬜ Chrome extension ↔ Windows app WebSocket handshake — never tested (same extension as Mac, but the Windows-side server has never run).

---

## Definition of "done" reality check (vs. CLAUDE.md acceptance criteria)

| Sprint | Mac | Windows |
|---|---|---|
| Sprint 1 (menubar + hardware skeleton + injection) | Mostly done — injection PASS verified live; BLE untested with real pen | Builds, nothing run |
| Sprint 2 (preview, history, browser extension, Sparkle) | History/preview verified in pipeline test; browser extension untested; Sparkle removed per HANDOFF.md notes (not currently in build) | Not started |
| Sprint 3 (AI correction, translation, Safari ext, security) | Not exercised this session | n/a |
| Sprint 4 (Windows full) | n/a | Almost entirely unverified beyond compiling |

---

## Next up (priority order)

1. Physical Windows PC session — install the CI-built `.msi`, set the Scanmarker account email in Settings → AI, pair a real Scanmarker Air over BLE, confirm a stroke round-trips through `RunOCR_V7` and produces real text, then test both injection paths (ValuePattern in Notepad/browser, clipboard fallback in Word), confirm tray UI renders, confirm WebSocket bridge/extension handshake.
2. Same class of fix for USB serial (`usb_serial.rs`) if/when a Scanmarker Air over USB needs to be supported — currently still assumes plain-text protocol.
3. Investigate phantom BLE "Connected" state on Mac cold launch — could be masking real bugs, fix before hardware testing.
4. Real Scanmarker pen test on Mac — BLE connect, scan, verify full pipeline with actual hardware (biggest unverified surface on Mac; Mac's protocol implementation is believed correct per cross-reference, but never confirmed against physical hardware).
5. Browser extension end-to-end test (both platforms) — inject into Google Docs/Gmail via the extension, not just native AX/UIA.
6. Apple Developer Program enrollment → notarize Mac DMG (24-48h latency, start early, zero eng time blocking).
7. EV Code Signing Certificate for Windows installer.
8. Once both hardware sessions land, add a "confirmed working targets" matrix (per-app: Word, Notepad, Outlook, Chrome, etc.) to this doc.

---
Last updated: 2026-07-04 (Mac core pipeline live-verified; Windows BLE/OCR protocol rewritten to match real hardware; both platforms now have a per-account Scanmarker email + local password gate (onboarding on Mac, Settings UI on Windows) — run 28718397397 green on both real CI targets; none of this hardware-tested yet)
