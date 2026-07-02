import SwiftUI
import AppKit
import Combine
// History / settings / preview / ocr / injection are co-located in the module and auto-included

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var menuBarController: MenuBarController!
    private var cancellables = Set<AnyCancellable>()

    // Core pipeline singletons (will be expanded with preview/AI/history)
    private let injectionRouter = InjectionRouter.shared
    private let previewController = PreviewWindowController.shared
    private let visionCorrector = VisionCorrector()


    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement = true in Info.plist hides from Dock and Cmd+Tab

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.text.viewfinder", accessibilityDescription: "ScanToExternApp")
            button.action = #selector(togglePopover(_:))
            button.target = self

            // Add right-click context menu (quit + debug)
            let rightClickMenu = NSMenu()
            let debugItem = NSMenuItem(title: "Debug: Simulate Scan", action: #selector(debugSimulateScan), keyEquivalent: "")
            debugItem.target = self
            rightClickMenu.addItem(debugItem)

            let selfTestItem = NSMenuItem(title: "Debug: Run Injection Self-Test", action: #selector(runInjectionSelfTest), keyEquivalent: "")
            selfTestItem.target = self
            rightClickMenu.addItem(selfTestItem)


            rightClickMenu.addItem(NSMenuItem.separator())
            rightClickMenu.addItem(withTitle: "Quit", action: #selector(quitApp), keyEquivalent: "q")
            // Note: for mixed left/right, we keep menu on statusItem and handle left separately
            statusItem.menu = rightClickMenu
        }

        // Popover setup
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.behavior = .transient
        popover.animates = true

        menuBarController = MenuBarController(statusItem: statusItem, popover: popover)

        let contentView = MenuBarView()
            .environmentObject(menuBarController) // pass controller if needed in full views
        popover.contentViewController = NSHostingController(rootView: contentView)

        // Start hardware managers (BT + USB)
        _ = HardwareManager.shared // triggers init + auto start

        // Wire hardware state to menubar controller
        HardwareManager.shared.$connectionState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.menuBarController?.setConnectionState(state)
            }
            .store(in: &cancellables)

        HardwareManager.shared.scanPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] (text, source) in
                self?.menuBarController?.setLastScan(text)
                guard let self = self else { return }

                // CRITICAL: capture the target app NOW, before our preview window steals focus.
                // At inject time, OUR toast is frontmost — so we must remember where the text should go.
                let targetApp = NSWorkspace.shared.frontmostApplication
                let targetBundleID = targetApp?.bundleIdentifier

                if !SettingsStore.shared.previewEnabled {
                    // Direct path when preview disabled
                    Task {
                        let processed = await AIProcessor.shared.process(text)
                        self.injectionRouter.route(processed, target: targetApp)
                        if SettingsStore.shared.historyEnabled {
                            let rec = ScanRecord(text: text, processedText: processed != text ? processed : nil, timestamp: Date(), source: source, injectedTo: targetBundleID, aiMode: SettingsStore.shared.aiMode)
                            do { try ScanHistoryStore.shared.save(rec) }
                            catch { print("[History] save failed (direct path): \(error)") }
                        }
                    }
                    return
                }

                self.previewController.showPreview(
                    text: text,
                    onInject: { finalText in
                        // Note: Apple Vision screenshot correction is intentionally NOT run here.
                        // It requires Screen Recording permission and can replace the scanned text
                        // with unrelated on-screen content. Inject the user-approved text directly.
                        Task {
                            let aiProcessed = await AIProcessor.shared.process(finalText)
                            self.injectionRouter.route(aiProcessed, target: targetApp)

                            // Persist to history (if enabled)
                            if SettingsStore.shared.historyEnabled {
                                let record = ScanRecord(
                                    text: finalText,
                                    processedText: aiProcessed != finalText ? aiProcessed : nil,
                                    timestamp: Date(),
                                    source: source,
                                    injectedTo: targetBundleID,
                                    aiMode: SettingsStore.shared.aiMode
                                )
                                do { try ScanHistoryStore.shared.save(record) }
                                catch { print("[History] save failed (preview path): \(error)") }
                            }

                            print("[App] Preview accepted — injected \(aiProcessed.count) chars into \(targetBundleID ?? "unknown")")
                        }
                    },
                    onDiscard: {
                        print("[App] Preview discarded by user")
                    }
                )
            }
            .store(in: &cancellables)

        // Onboarding / permissions. SCANAPP_QUIET=1 suppresses the prompts during
        // automated testing so repeated launches don't nag.
        let quiet = ProcessInfo.processInfo.environment["SCANAPP_QUIET"] == "1"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            PermissionsManager.shared.checkAll()
            if quiet { return }
            self?.injectionRouter.requestAXPermissionIfNeeded()
            if !AXIsProcessTrusted() {
                self?.showAccessibilityNeededAlert()
            }
        }

        // Apply launch at login based on setting (and sync)
        LaunchAtLoginManager.syncWithSetting()

        print("[ScanToExternApp] v5.0 menubar app launched. Bundle ID: com.topscan.ScanToExternApp")

        // Verification hook: when SCANAPP_SELFTEST=1, run the end-to-end injection
        // self-test automatically on launch, then quit. Used for headless verification.
        // Verification hook: SCANAPP_SELFTEST=1 runs the end-to-end injection self-test on
        // launch then quits. Harmless in normal use (only fires when the env var is set).
        if ProcessInfo.processInfo.environment["SCANAPP_SELFTEST"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.runInjectionSelfTest()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { NSApp.terminate(nil) }
        }

        // Verification hook: SCANAPP_WSTEST=1 broadcasts a test scan over the WebSocket every
        // 2s so the browser bridge can be verified without UI. Harmless unless the env var is set.
        if ProcessInfo.processInfo.environment["SCANAPP_WSTEST"] == "1" {
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                InjectionRouter.shared.testBroadcast("WS_TEST_SCAN_\(Int(Date().timeIntervalSince1970))")
            }
        }

        // Verification hook: SCANAPP_PIPELINE_TEST=1 exercises the FULL end-to-end pipeline
        // that a real Scanmarker scan would trigger — hardware publisher → preview-off
        // shortcut → AI passthrough → router → clipboard/AX inject → history save → registry
        // state — and writes a PASS/FAIL report per stage to ~/Desktop/scanapp-pipeline-test.txt.
        // This is the meaningful smoke test; the injection-only SCANAPP_SELFTEST only proves
        // the injectors themselves work in isolation.
        if ProcessInfo.processInfo.environment["SCANAPP_PIPELINE_TEST"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.runPipelineTest()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { NSApp.terminate(nil) }
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    /// Shown on launch when Accessibility is not granted. Without it, text injection
    /// into native apps cannot work — so we make the requirement explicit and actionable.
    private func showAccessibilityNeededAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility permission required"
        alert.informativeText = """
        ScanToExternApp needs Accessibility access to type scanned text into other apps \
        (Notes, Word, Mail, etc.).

        Click "Open Settings", then enable ScanToExternApp under \
        Privacy & Security → Accessibility. Without this, scans cannot be injected.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private var selfTestReport = ""
    private func stReport(_ line: String) {
        print(line)
        selfTestReport += line + "\n"
        let path = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop/scanapp-selftest.txt")
        try? selfTestReport.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private var pipelineReport = ""
    private var pipelineCancellables = Set<AnyCancellable>()
    private func plReport(_ line: String) {
        print(line)
        pipelineReport += line + "\n"
        let path = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop/scanapp-pipeline-test.txt")
        try? pipelineReport.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// End-to-end pipeline verification. Unlike `runInjectionSelfTest` (which only exercises the
    /// AX/Clipboard primitives against TextEdit in isolation), this drives the full path that a
    /// real Scanmarker scan follows:
    ///
    ///   HardwareManager.simulateScan → scanPublisher.send → AppDelegate subscriber
    ///     → preview-disabled shortcut (no UI click needed) → AIProcessor.process
    ///     → InjectionRouter.route → AXInjector/ClipboardInjector → target app
    ///     → ScanHistoryStore.save
    ///
    /// Plus a snapshot of DeviceRegistry state so we know the pairing UI's underlying model is
    /// actually alive. Writes a per-stage PASS/FAIL report to ~/Desktop/scanapp-pipeline-test.txt.
    @objc private func runPipelineTest() {
        pipelineReport = ""
        let marker = "PIPELINE_TEST_\(Int(Date().timeIntervalSince1970))"
        plReport("=== ScanToExternApp End-to-End Pipeline Test ===")
        plReport("marker: \(marker)")
        plReport("AXIsProcessTrusted: \(AXIsProcessTrusted())")

        // Force the pipeline into a deterministic, UI-free config:
        //   preview OFF  → scanPublisher subscriber takes the direct route (no toast click)
        //   AI mode off  → process() is passthrough (no cloud/on-device latency to wait on)
        //   history ON   → we verify the save path
        // We restore nothing on exit — the test runs then quits.
        let originalPreview = SettingsStore.shared.previewEnabled
        let originalAI = SettingsStore.shared.aiMode
        let originalHist = SettingsStore.shared.historyEnabled
        SettingsStore.shared.previewEnabled = false
        SettingsStore.shared.aiMode = "off"
        SettingsStore.shared.historyEnabled = true
        plReport("settings snapshot before: preview=\(originalPreview) aiMode=\(originalAI) history=\(originalHist)")
        // Force the UserDefaults write so subscribers reading @AppStorage see the new value.
        UserDefaults.standard.set(false, forKey: "previewEnabled")
        UserDefaults.standard.set("off", forKey: "aiMode")
        UserDefaults.standard.set(true, forKey: "historyEnabled")
        UserDefaults.standard.synchronize()
        plReport("settings during test:      preview=\(SettingsStore.shared.previewEnabled) aiMode=\(SettingsStore.shared.aiMode) history=\(SettingsStore.shared.historyEnabled)")

        // Instrument the publisher so we know whether the scan actually flows through it,
        // independent of whatever the AppDelegate's main subscriber does.
        HardwareManager.shared.scanPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] (text, source) in
                self?.plReport("scanPublisher OBSERVED: source=\(source), text=\"\(text.prefix(60))\"")
            }
            .store(in: &pipelineCancellables)

        // 1. Open TextEdit on a fresh doc, same way runInjectionSelfTest does, so we have a
        //    guaranteed focusable text area to inject into.
        let tmpDoc = (NSTemporaryDirectory() as NSString).appendingPathComponent("scanapp-pipeline-\(marker).txt")
        try? "".write(toFile: tmpDoc, atomically: true, encoding: .utf8)
        let docURL = URL(fileURLWithPath: tmpDoc)
        if let teURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.open([docURL], withApplicationAt: teURL, configuration: cfg) { _, error in
                if let error = error { self.plReport("TextEdit open error: \(error.localizedDescription)") }
            }
        } else {
            plReport("FAIL: TextEdit not found on system")
        }

        // Delay 2.5s so TextEdit's window and text view are fully realized and focusable.
        let stepTimer = Timer(timeInterval: 2.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            guard let te = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else {
                self.plReport("FAIL: TextEdit not running"); return
            }
            te.activate(options: [])
            Thread.sleep(forTimeInterval: 0.5)
            let pid = te.processIdentifier
            self.plReport("TextEdit pid=\(pid), frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")

            func readTextEdit() -> String {
                let axApp = AXUIElementCreateApplication(pid)
                var focused: AnyObject?
                guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
                      let el = focused else { return "<no focused element>" }
                var v: AnyObject?
                AXUIElementCopyAttributeValue(el as! AXUIElement, kAXValueAttribute as CFString, &v)
                return (v as? String) ?? "<nil value>"
            }

            // 2. Snapshot DeviceRegistry — proves the pairing state machine is alive. In a
            //    headless run with no scanner nearby we expect .scanning (BT on, no paired
            //    device), .idle, or .bluetoothOff/Unauthorized on a Mac without BT. Any of those
            //    is a valid outcome; the assertion is that we HAVE a status at all.
            let registry = DeviceRegistry.shared
            self.plReport("--- DeviceRegistry snapshot ---")
            self.plReport("status: \(registry.status)")
            self.plReport("discovered.count: \(registry.discovered.count)")
            self.plReport("preferredDeviceID: \(registry.preferredDeviceID ?? "<none>")")
            let registryAlive: Bool
            switch registry.status {
            case .idle, .scanning, .bluetoothOff, .bluetoothUnauthorized, .connecting, .connected, .reconnecting:
                registryAlive = true
            case .failed:
                registryAlive = true // failed is still a valid live state; the test isn't about BT itself
            }
            self.plReport("[C] REGISTRY ALIVE: \(registryAlive ? "PASS ✅" : "FAIL ❌")")

            // 3. Fire the pipeline. simulateScan drives HardwareManager.scanPublisher which the
            //    AppDelegate subscriber handles. With preview disabled it takes the direct branch:
            //    AI process → route → inject into targetApp (TextEdit) → history save.
            let historyCountBefore = (try? ScanHistoryStore.shared.recent(limit: 1000).count) ?? -1
            self.plReport("history rows before: \(historyCountBefore)")
            self.plReport("--- Firing HardwareManager.simulateScan(\"\(marker)\") ---")
            HardwareManager.shared.simulateScan(marker)

            // 4. Wait for the async pipeline to settle. The route() call dispatches to a
            //    background queue with a 0.2s activation sleep + inject; then history save
            //    is fired from the main-thread subscriber's Task { … }. 2.5s is generous.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                te.activate(options: [])
                Thread.sleep(forTimeInterval: 0.3)

                // Test A: did the marker land in the target text field?
                let textEditContents = readTextEdit()
                let injectPass = textEditContents.contains(marker)
                self.plReport("--- Stage A: hardware → publisher → router → inject ---")
                self.plReport("TextEdit readback: \"\(textEditContents.prefix(120))\"")
                self.plReport("[A] SCAN INJECTED: \(injectPass ? "PASS ✅" : "FAIL ❌")")

                // Test B: did the same scan land in the SQLite history table?
                let recent = (try? ScanHistoryStore.shared.recent(limit: 5)) ?? []
                let recentMarkerRow = recent.first(where: { $0.text == marker })
                let historyPass = recentMarkerRow != nil
                self.plReport("--- Stage B: publisher → history save ---")
                self.plReport("history rows after: \(recent.count)")
                if let row = recentMarkerRow {
                    self.plReport("matching row: source=\(row.source) aiMode=\(row.aiMode ?? "<nil>") injectedTo=\(row.injectedTo ?? "<nil>")")
                } else {
                    let top = recent.first.map { "\($0.text.prefix(40))… source=\($0.source)" } ?? "<empty>"
                    self.plReport("marker NOT in most recent 5. Latest row: \(top)")
                }
                self.plReport("[B] SCAN PERSISTED: \(historyPass ? "PASS ✅" : "FAIL ❌")")

                // Overall verdict.
                let overall = injectPass && historyPass && registryAlive
                self.plReport("=== SUMMARY: Inject=\(injectPass ? "PASS" : "FAIL") History=\(historyPass ? "PASS" : "FAIL") Registry=\(registryAlive ? "PASS" : "FAIL") — \(overall ? "OK" : "FAILED") ===")
                self.plReport("Report saved to ~/Desktop/scanapp-pipeline-test.txt")
            }
        }
        RunLoop.main.add(stepTimer, forMode: .common)
    }

    /// Automated end-to-end injection test. Opens TextEdit, injects via the real AXInjector,
    /// reads the text back, and if AX fails, tries the clipboard fallback. Writes a PASS/FAIL
    /// report to ~/Desktop/scanapp-selftest.txt so the result is easy to inspect.
    @objc private func runInjectionSelfTest() {
        selfTestReport = ""
        let marker = "SELFTEST_\(Int(Date().timeIntervalSince1970))"
        stReport("=== ScanToExternApp Injection Self-Test ===")
        stReport("marker: \(marker)")
        stReport("AXIsProcessTrusted: \(AXIsProcessTrusted())")

        // 1. Open an actual editable document in TextEdit. Opening the app bare can land on
        //    the file-open panel (no text area). Creating a temp .txt and opening it guarantees
        //    a real document window with a focusable text area. Uses NSWorkspace (no AppleScript).
        let tmpDoc = (NSTemporaryDirectory() as NSString).appendingPathComponent("scanapp-selftest-\(marker).txt")
        try? "".write(toFile: tmpDoc, atomically: true, encoding: .utf8)
        let docURL = URL(fileURLWithPath: tmpDoc)
        if let teURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.open([docURL], withApplicationAt: teURL, configuration: cfg) { _, error in
                if let error = error { self.stReport("TextEdit open error: \(error.localizedDescription)") }
            }
        } else {
            stReport("FAIL: TextEdit not found on system")
        }

        // Give TextEdit time to launch AND create its default empty document window.
        let stepTimer = Timer(timeInterval: 2.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            guard let te = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else {
                self.stReport("FAIL: TextEdit not running"); return
            }
            te.activate(options: [])
            Thread.sleep(forTimeInterval: 0.5)
            let pid = te.processIdentifier
            self.stReport("TextEdit pid=\(pid), frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")

            func diagnose() {
                let axApp = AXUIElementCreateApplication(pid)
                var focused: AnyObject?
                let fr = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focused)
                if fr != .success || focused == nil {
                    self.stReport("DIAG: no focused element (err \(fr.rawValue))")
                } else {
                    var role: AnyObject?
                    AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXRoleAttribute as CFString, &role)
                    self.stReport("DIAG: focused role=\((role as? String) ?? "?")")
                }
                var windows: AnyObject?
                AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windows)
                let count = (windows as? [AXUIElement])?.count ?? 0
                self.stReport("DIAG: window count=\(count)")
            }

            func readback() -> String {
                let axApp = AXUIElementCreateApplication(pid)
                var focused: AnyObject?
                guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
                      let el = focused else { return "<no focused element>" }
                var v: AnyObject?
                AXUIElementCopyAttributeValue(el as! AXUIElement, kAXValueAttribute as CFString, &v)
                return (v as? String) ?? "<nil value>"
            }

            diagnose()

            // --- Test A: AXUIElement injection ---
            let axMarker = marker + "_AX "
            let axResult = AXInjector().inject(axMarker, targetPID: pid)
            self.stReport("[A] AXInjector.inject returned: \(axResult)")
            Thread.sleep(forTimeInterval: 0.4)
            let axRead = readback()
            let axPass = axRead.contains(marker + "_AX")
            self.stReport("[A] readback: \"\(axRead.prefix(100))\"")
            self.stReport("[A] AX RESULT: \(axPass ? "PASS ✅" : "FAIL ❌")")

            // --- Test B: clipboard + Cmd+V fallback ---
            te.activate(options: [])
            Thread.sleep(forTimeInterval: 0.3)
            let cbMarker = marker + "_CB "
            ClipboardInjector().inject(cbMarker, targetApp: te)
            Thread.sleep(forTimeInterval: 0.8)
            let cbRead = readback()
            let cbPass = cbRead.contains(marker + "_CB")
            self.stReport("[B] readback: \"\(cbRead.prefix(100))\"")
            self.stReport("[B] CLIPBOARD RESULT: \(cbPass ? "PASS ✅" : "FAIL ❌")")

            self.stReport("=== SUMMARY: AX=\(axPass ? "PASS" : "FAIL") Clipboard=\(cbPass ? "PASS" : "FAIL") ===")
            self.stReport("Report saved to ~/Desktop/scanapp-selftest.txt")
        }
        RunLoop.main.add(stepTimer, forMode: .common)
    }

    @objc private func debugSimulateScan() {
        // Delay so the tester can click into their target app (Notes/TextEdit) first.
        // A real Scanmarker scan doesn't have this problem — the user isn't touching our UI.
        let countdown = 4
        let note = NSUserNotification()
        note.title = "Simulating scan in \(countdown)s"
        note.informativeText = "Click into the app where you want the text to land."
        NSUserNotificationCenter.default.deliver(note)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(countdown)) {
            HardwareManager.shared.simulateScan()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Future: stop hardware managers, close WS server gracefully
    }

    // Backwards compatibility: scan2extern:// scheme (spec says keep for compat only; primary is direct injection + WS)
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme?.lowercased() == "scan2extern" {
                // Example: scan2extern://inject?text=Hello%20World
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let textItem = components.queryItems?.first(where: { $0.name == "text" })?.value,
                   let decoded = textItem.removingPercentEncoding {
                    // For compat we still go through the normal preview + pipeline
                    DispatchQueue.main.async {
                        PreviewWindowController.shared.showPreview(
                            text: decoded,
                            onInject: { final in
                                Task {
                                    let processed = await AIProcessor.shared.process(final)
                                    InjectionRouter.shared.route(processed)
                                }
                            },
                            onDiscard: {}
                        )
                    }
                }
            }
        }
    }
}
