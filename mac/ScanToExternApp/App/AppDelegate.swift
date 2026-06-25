import SwiftUI
import AppKit
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var menuBarController: MenuBarController!
    private var cancellables = Set<AnyCancellable>()

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
                // Future: trigger preview + injection pipeline here
                print("[App] Received scan from \(source), length=\(text.count)")
            }
            .store(in: &cancellables)

        // Onboarding / permissions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            PermissionsManager.shared.checkAll()
            // In production: if !hasAccessibility { PermissionsManager.shared.requestAccessibility() }
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
