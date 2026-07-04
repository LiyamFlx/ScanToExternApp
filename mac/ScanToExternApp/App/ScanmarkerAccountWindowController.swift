import AppKit
import SwiftUI

/// First-launch account setup: email + a local password.
///
/// This is NOT real authentication — Scanmarker's cloud OCR service only checks the email
/// field to unlock real recognition, no password. The password here is purely a local gate
/// (hashed in Keychain) so a shared machine can't have someone silently swap the configured
/// email without confirming "yes, it's me." Skippable — the app keeps working with the
/// shared default email (SettingsStore.scanmarkerEmail) until the user sets their own here
/// or later in Settings → AI.
enum ScanmarkerAccountWindowController {
    private static var window: NSWindow?

    static func show(onDone: @escaping () -> Void) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = ScanmarkerAccountView(
            onDone: {
                close()
                onDone()
            }
        )
        let host = NSHostingController(rootView: content)

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Set Up Your Scanmarker Account"
        w.contentViewController = host
        w.center()
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        window?.orderOut(nil)
    }
}

private struct ScanmarkerAccountView: View {
    var onDone: () -> Void

    @State private var email: String = ""
    @State private var password: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up your Scanmarker account")
                    .font(.title2.weight(.semibold))
                Text("Your pen's cloud OCR needs an email to recognize text. Add a local password so only you can change it on this Mac.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            Text("No verification, no server — this just confirms it's you if you change the account later.")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            HStack {
                Button("Skip for now") { onDone() }
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420, height: 320)
    }

    private func save() {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        SettingsStore.shared.scanmarkerEmail = trimmed
        if !password.isEmpty {
            KeychainManager.saveScanmarkerPasswordHash(password)
        }
        onDone()
    }
}
