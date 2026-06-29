# ScanToExternApp v5.0 — Install Guide (macOS)

A menubar companion for the Scanmarker pen scanner. Scans inject into any focused
text field — native apps (Notes, Word, Mail) and web apps (Google Docs, Gmail) via the
browser extension.

## 1. Install the app

1. Open **ScanToExternApp-5.0.0.dmg**.
2. Drag **ScanToExternApp** onto the **Applications** folder.
3. Eject the DMG.

## 2. First launch (one-time Gatekeeper step)

This build is signed with a self-signed certificate (not an Apple Developer ID), so the
first launch needs a manual approval:

1. Open **Applications**, **right-click** ScanToExternApp → **Open**.
2. In the dialog, click **Open** again.

After this first time, it launches normally by double-click. You only do this once.

There is **no Dock icon** — look for the scanner icon (a document with a viewfinder) in the
**menubar at the top-right** of the screen.

## 3. Grant Accessibility permission (required for typing into apps)

On first launch the app asks for Accessibility access. This lets it type scanned text into
other apps.

1. Click **Open Settings** in the prompt (or open  → System Settings → Privacy & Security
   → **Accessibility**).
2. Toggle **ScanToExternApp** **ON** (enter your password if asked).

You only grant this once — it persists across launches.

## 4. (Optional) Browser extension — for Google Docs, Gmail, web apps

Native injection covers desktop apps. For text fields inside the browser, load the extension:

1. Open Chrome → go to `chrome://extensions`.
2. Turn on **Developer mode** (top-right).
3. Click **Load unpacked** and select the **BrowserExtension** folder.
4. The extension connects automatically to the running app (look for the green status dot
   in its popup).

The app must be running for the extension to receive scans.

## 5. Try it without hardware

Click the menubar icon → **Test Scan** (or right-click the icon → *Debug: Simulate Scan*).
A preview toast appears; click **Inject** and the text lands in whatever app/field is focused.

---

## Notes

- **Bluetooth Scanmarker:** the app auto-scans for the Scanmarker (Nordic UART) on launch.
  Grant Bluetooth permission if prompted.
- **USB Scanmarker:** plug in; the app polls for the serial device automatically.
- **AI features & history** are configured in **Settings** (menubar → Settings).
- Uninstall: quit from the menubar (right-click → Quit), then drag the app to Trash.
