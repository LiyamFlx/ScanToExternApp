# Project Handoff — read this first

Status notes for continuing work across machines/sessions. Last updated: 2026-06-30.

## TL;DR of where things stand

- **Mac app: WORKS and re-verified.** Native injection (Accessibility + clipboard)
  passes the automated self-test (AX=PASS, Clipboard=PASS), the WebSocket bridge
  delivers correctly framed scans to clients, and a clean signed DMG
  (`mac/build/ScanToExternApp-5.0.0.dmg`, ~2.2 MB) mounts and deep-verifies.
- Distribution: see **NOTARIZATION.md** for the exact requirements + commands to
  turn this into a zero-warnings DMG with an Apple Developer ID.
- **Windows app: written and compiles, but never built into a runnable app or tested.**
  Must be built ON a Windows machine.

## What was done this session (2026-06-30)

1. **Re-verified the build end-to-end** after the prior session.
   - Clean Release build via xcodegen + xcodebuild: BUILD SUCCEEDED, .app = 5.7 MB.
   - WebSocket pipeline verified live: handshake completes, 3 scan frames received
     by a Python client, all correctly framed JSON `{"type":"scan","text":...,"id":...}`.
   - Self-test report: AX=PASS, Clipboard=PASS in `~/Desktop/scanapp-selftest.txt`.

2. **Polish + edge-case fixes**:
   - Removed stale `SUFeedURL` / `SUPublicEDKey` Sparkle keys from Info.plist
     (Sparkle was removed in the previous session; the keys did nothing).
   - WebSocket `broadcastScan` now caps text at 100,000 chars (CLAUDE.md security
     invariant).
   - `InjectionRouter.route` early-returns on empty/whitespace text so an empty
     simulated/URL scan can't trigger 0-byte focus theft.

3. **Signing recipe upgraded** to a stable designated requirement
   (`identifier "com.topscan.ScanToExternApp" and certificate leaf[subject.CN] = "ScanToExternApp Self-Signed"`).
   - With a Developer ID this trick fully eliminates re-granting Accessibility
     across rebuilds (TCC matches the requirement, not the cdhash).
   - With THIS self-signed cert, TCC still pins to cdhash, so each rebuild + reinstall
     still revokes the existing Accessibility grant. Acceptable for our dev loop,
     trivially solved once notarized.

4. **DMG built + signed + verified**: mounts as `/Volumes/ScanToExternApp`, the
   app inside passes `codesign --verify --deep --strict`, deep-launches without
   crashing.

5. **NOTARIZATION.md** documents exactly what's needed to ship a zero-warnings
   DMG: Apple Developer Program membership, Developer ID Application cert, an
   app-specific password for notarytool, plus the full sign + notarize + staple
   sequence.

## How to build + run the MAC app

```bash
cd mac
# Regenerate the Xcode project from project.yml (requires xcodegen, brew installed):
/opt/homebrew/bin/xcodegen generate
# Build Release:
xcodebuild -project ScanToExternApp.xcodeproj -scheme ScanToExternApp \
  -configuration Release -derivedDataPath build build
# App is at: build/Build/Products/Release/ScanToExternApp.app
```

Sign with the local self-signed cert (created once via `mac/make-signing-cert.sh`).
Use the stable designated requirement so the Accessibility grant survives rebuilds
once we go to a Developer ID:

```bash
cat > /tmp/scanapp.entitlements <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict></plist>
EOF
codesign --force --sign "ScanToExternApp Self-Signed" --options runtime \
  --requirements '=designated => identifier "com.topscan.ScanToExternApp" and certificate leaf[subject.CN] = "ScanToExternApp Self-Signed"' \
  --entitlements /tmp/scanapp.entitlements \
  build/Build/Products/Release/ScanToExternApp.app
```

Self-test injection (PASS/FAIL report written to `~/Desktop/scanapp-selftest.txt`):

```bash
# IMPORTANT: launch via `open`, not by executing the inner Mach-O directly.
# Direct `Contents/MacOS/...` execution bypasses LaunchServices and TCC will
# not match the running process against the Accessibility grant, so the test
# spuriously reports AXIsProcessTrusted: false. The `--env` flags propagate.
open -W -n /Applications/ScanToExternApp.app \
  --env SCANAPP_SELFTEST=1 --env SCANAPP_QUIET=1
cat ~/Desktop/scanapp-selftest.txt
```

WebSocket verification hook: launch with `SCANAPP_WSTEST=1` (same `open --env`
form) and the app broadcasts a `WS_TEST_SCAN_<timestamp>` every 2s — useful to
verify the browser extension / any WS client without hardware.

## Building the DMG

```bash
STAGE=/tmp/scanapp-dmg-stage
rm -rf "$STAGE" && mkdir "$STAGE"
cp -R mac/build/Build/Products/Release/ScanToExternApp.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "ScanToExternApp" -srcfolder "$STAGE" \
  -ov -format UDZO mac/build/ScanToExternApp-5.0.0.dmg
codesign --sign "ScanToExternApp Self-Signed" mac/build/ScanToExternApp-5.0.0.dmg
```

## How to build the WINDOWS app (MUST be done on Windows)

The Rust code compiles (verified via `cargo check` on Mac), but the Windows-only
injection/tray/installer code only builds on Windows. On a Windows 10/11 PC:

```powershell
# Prereqs: install Rust (rustup), Node.js, and the Tauri CLI:
#   https://tauri.app/start/prerequisites/  (needs MSVC build tools + WebView2)
cargo install tauri-cli

cd windows\src-tauri
cargo tauri dev      # tray app, dev
cargo tauri build    # .msi + .exe installers in target\release\bundle\
```

See `windows/WINDOWS_SETUP.md` and Sprint 4 acceptance criteria in `CLAUDE.md`.

## Distribution

Read **NOTARIZATION.md** for the path to a zero-warnings Mac DMG. TL;DR: pay
Apple $99/yr for Developer Program membership, create a Developer ID Application
cert, give me the cert ID + Apple ID + Team ID + an app-specific password, and
I'll do the sign + notarize + staple sequence end-to-end.

Without notarization, the current self-signed DMG works but users see a
Gatekeeper warning the first time. Workaround: right-click → Open in Finder
once, OR `xattr -dr com.apple.quarantine /Applications/ScanToExternApp.app`.

## Important: starting a fresh session (e.g. on Windows)

A new chat does NOT remember this conversation. To get back up to speed, tell the
assistant: **"Read HANDOFF.md and CLAUDE.md, then continue."** Everything needed
is in the repo (this file, CLAUDE.md = full spec, NOTARIZATION.md = distribution,
git history = what changed).
