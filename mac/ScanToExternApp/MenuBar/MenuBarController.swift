import AppKit
import SwiftUI
import Combine

// Manages the NSStatusItem and popover interactions
// State is driven by HardwareManager (later steps)

class MenuBarController: NSObject, ObservableObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover

    @Published var connectionState: ConnectionState = .disconnected
    @Published var lastScanPreview: String = ""
    @Published var deviceName: String = "No device"
    @Published var batteryPercent: Int?

    init(statusItem: NSStatusItem, popover: NSPopover) {
        self.statusItem = statusItem
        self.popover = popover
        super.init()
        updateStatusIcon()
    }

    func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let symbol: String
        switch connectionState {
        case .disconnected: symbol = "doc.text.viewfinder"
        case .connected: symbol = "doc.text.viewfinder"
        case .scanning: symbol = "waveform.path.ecg"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ScanToExternApp \(connectionState.rawValue)")
    }

    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func hidePopover() {
        popover.performClose(nil)
    }

    func setConnectionState(_ state: ConnectionState) {
        connectionState = state
        updateStatusIcon()
    }

    func setLastScan(_ text: String) {
        lastScanPreview = String(text.prefix(80))
    }
}

enum ConnectionState: String, CaseIterable {
    case disconnected = "Disconnected"
    case connected = "Connected"
    case scanning = "Scanning"
}
