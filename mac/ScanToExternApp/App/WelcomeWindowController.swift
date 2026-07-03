import AppKit
import SwiftUI

/// A real, visible window shown on first launch so users KNOW the app is running.
/// A pure LSUIElement menubar app is invisible after double-click — no Dock icon,
/// no window, only a small icon in the menubar that many users don't notice or
/// can't find (especially with third-party menu bar managers hiding overflow).
/// This window gives explicit "the app is running" feedback and a big button that
/// opens the menubar popover.
enum WelcomeWindowController {
    private static var window: NSWindow?

    static func show(togglePopover: @escaping () -> Void) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = WelcomeView(
            openPanel: {
                togglePopover()
                close()
            },
            close: { close() }
        )
        let host = NSHostingController(rootView: content)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "ScanToExternApp"
        w.contentViewController = host
        w.center()
        w.isReleasedWhenClosed = false
        w.level = .floating          // above other apps so users can't miss it
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        window?.orderOut(nil)
    }
}

private struct WelcomeView: View {
    var openPanel: () -> Void
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ScanToExternApp is running")
                        .font(.title2.weight(.semibold))
                    Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "5.0")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            Text("Where the app lives")
                .font(.headline)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.up.right")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                Text("Look at the **top-right of your screen menubar** for the scanner icon (a document with a viewfinder). Left-click it to open the panel, right-click for debug options.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("What it does")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                bullet("Pair a Scanmarker pen (Bluetooth or USB) from the Devices panel.")
                bullet("Scans automatically inject into whatever text field is focused — Notes, Mail, Word, Google Docs, and any web input via the browser extension.")
                bullet("Scan history is saved locally in SQLite. AI processing is opt-in.")
            }

            Spacer()

            HStack {
                Toggle("Show this window every launch", isOn: Binding(
                    get: { !UserDefaults.standard.bool(forKey: "hideWelcomeOnLaunch") },
                    set: { UserDefaults.standard.set(!$0, forKey: "hideWelcomeOnLaunch") }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
                Spacer()
                Button("Close") { close() }
                Button("Open Panel Now") { openPanel() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 420)
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "circle.fill").font(.system(size: 4)).padding(.top, 7).foregroundColor(.secondary)
            Text(.init(text)).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }
}
