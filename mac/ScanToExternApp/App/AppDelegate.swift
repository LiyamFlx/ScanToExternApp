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
    private let injectionRouter = InjectionRouter()
    private let previewController = PreviewWindowController()
    private let visionCorrector = VisionCorrector()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement = true in Info.plist hides from Dock and Cmd+Tab

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.text.viewfinder", accessibilityDescription: "ScanToExternApp")
            button.action = #selector(togglePopover(_:))
            button.target = self

            // Add right-click context menu (quit)
            let rightClickMenu = NSMenu()
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

                // Phase 3: Show preview toast. On inject (or auto-timeout), optionally run vision/AI then route.
                guard let self = self else { return }

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

    func applicationWillTerminate(_ aNotification: Notification) {
        // Future: stop hardware managers, close WS server gracefully
    }
}
