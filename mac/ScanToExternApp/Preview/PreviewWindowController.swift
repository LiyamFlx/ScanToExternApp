import AppKit
import SwiftUI

/// Floating, borderless, always-on-top toast window for 1-2s scan preview.
/// Positioned bottom-right of main screen.
/// Auto-dismisses (injects) after timeout unless user interacts.
final class PreviewWindowController: NSWindowController {
    private var hostingController: NSHostingController<PreviewView>?
    private var currentText: String = ""
    private var onFinalInject: ((String) -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 160),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.init(window: window)
    }

    func showPreview(text: String, onInject: @escaping (String) -> Void, onDiscard: @escaping () -> Void) {
        currentText = text
        onFinalInject = onInject

        let previewView = PreviewView(
            text: text,
            onInject: { [weak self] finalText in
                self?.dismiss()
                onInject(finalText)
            },
            onDiscard: { [weak self] in
                self?.dismiss()
                onDiscard()
            }
        )

        let host = NSHostingController(rootView: previewView)
        hostingController = host

        window?.contentViewController = host
        window?.contentView = host.view

        // Position bottom right
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let winSize = host.view.fittingSize
            let x = screenFrame.maxX - winSize.width - 24
            let y = screenFrame.minY + 24
            window?.setFrame(NSRect(x: x, y: y, width: winSize.width, height: winSize.height), display: true)
        }

        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func dismiss() {
        window?.orderOut(nil)
        hostingController = nil
    }
}
