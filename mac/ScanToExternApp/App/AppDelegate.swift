import SwiftUI
import AppKit
import Combine
import Sparkle
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

    // Sparkle 2 auto-updater (configured via Info.plist SUFeedURL + SUPublicEDKey)
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

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

            let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            updateItem.target = self
            rightClickMenu.addItem(updateItem)

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

                // Phase 3: Show preview toast (unless disabled in Settings). On inject (or auto-timeout), run vision/AI then route.
                guard let self = self else { return }

                if !SettingsStore.shared.previewEnabled {
                    // Direct path when preview disabled
                    Task {
                        let processed = await AIProcessor.shared.process(text)
                        self.injectionRouter.route(processed)
                        if SettingsStore.shared.historyEnabled {
                            let rec = ScanRecord(text: text, processedText: processed != text ? processed : nil, timestamp: Date(), source: "hardware", injectedTo: NSWorkspace.shared.frontmostApplication?.bundleIdentifier, aiMode: SettingsStore.shared.aiMode)
                            try? ScanHistoryStore.shared.save(rec)
                        }
                    }
                    return
                }

                self.previewController.showPreview(
                    text: text,
                    onInject: { finalText in
                        // Optional secondary OCR correction (can be conditional on setting or low-trust heuristic)
                        self.visionCorrector.correct(hardwareText: finalText) { corrected in
                            Task {
                                let aiProcessed = await AIProcessor.shared.process(corrected)
                                self.injectionRouter.route(aiProcessed)

                                // Persist to history (if enabled)
                                if SettingsStore.shared.historyEnabled {
                                    let record = ScanRecord(
                                        text: finalText,
                                        processedText: aiProcessed != finalText ? aiProcessed : nil,
                                        timestamp: Date(),
                                        source: "hardware",
                                        injectedTo: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                        aiMode: SettingsStore.shared.aiMode
                                    )
                                    try? ScanHistoryStore.shared.save(record)
                                }

                                print("[App] Preview accepted — injected after AI (\(aiProcessed.count) chars)")
                            }
                        }
                    },
                    onDiscard: {
                        print("[App] Preview discarded by user")
                    }
                )
            }
            .store(in: &cancellables)

        // Onboarding / permissions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            PermissionsManager.shared.checkAll()
            self?.injectionRouter.requestAXPermissionIfNeeded()
        }

        // Apply launch at login based on setting (and sync)
        LaunchAtLoginManager.syncWithSetting()

        print("[ScanToExternApp] v5.0 menubar app launched. Bundle ID: com.topscan.ScanToExternApp")
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

    @objc private func debugSimulateScan() {
        HardwareManager.shared.simulateScan()
    }

    @objc private func checkForUpdates() {
        updaterController.checkForUpdates(nil)
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
