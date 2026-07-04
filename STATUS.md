# STATUS

Update at end of every session — source of truth, not memory/chat history.

## Mac
- Build (CI): ✅ passing — 2026-07-04
- Self-test (AX/Clipboard): ✅ PASS
- BLE hardware (real pen): 🔄 in progress
- Notarization: ❌ blocked — needs Developer ID enrollment ($99/yr)
- DMG: ✅ built, signed (self-signed cert only)

## Windows
- Build (CI): 🔄 fix pushed, awaiting confirm
- Build (real PC): ⬜ never run
- BLE hardware (real pen): ⬜ untested
- Injection (UIA): ⬜ untested
- Installer (.msi/.exe): ⬜ never generated

## Next up
1. Confirm Windows CI green after npm-step fix
2. Real-pen BLE test on Mac
3. Physical Windows PC session — BLE + UIA injection test
4. Developer ID enrollment → notarize Mac DMG

---
Last updated: 2026-07-04
