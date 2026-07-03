import SwiftUI

/// Simple first-launch / permissions checklist as mentioned in the spec.
/// Appears as a sheet from the menubar popover or on launch if needed.
struct PermissionsOnboardingView: View {
    @ObservedObject var permissions = PermissionsManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showExtensionHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to ScanToExternApp")
                .font(.title2.bold())

            Text("To use your Scanmarker pen, please grant these permissions:")

            VStack(alignment: .leading, spacing: 12) {
                PermissionRow(
                    title: "Accessibility",
                    granted: permissions.hasAccessibility,
                    action: {
                        PermissionsManager.shared.requestAccessibility()
                    },
                    description: "Required to inject text directly into Word, Notes, Mail, etc."
                )

                PermissionRow(
                    title: "Bluetooth",
                    granted: permissions.hasBluetooth,
                    action: {
                        // Bluetooth is prompted automatically when we start scanning
                        HardwareManager.shared.forceRescan()
                    },
                    description: "Required to connect to Scanmarker Air over Bluetooth."
                )
            }

            Divider()

            Text("Optional but recommended:")
                .font(.headline)

            VStack(alignment: .leading) {
                Button("Install Browser Extension (Chrome / Edge / Safari)") {
                    showExtensionHelp = true
                }

                Text("Enables injection into Google Docs, Gmail, Twitter, and any web app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 420)
        .sheet(isPresented: $showExtensionHelp) {
            VStack(spacing: 12) {
                Text("Browser Extension")
                    .font(.headline)
                Text("1. In Chrome/Edge: go to chrome://extensions, enable Developer mode, Load unpacked, select the BrowserExtension folder.")
                Text("2. For Safari: create a Safari Web Extension target in Xcode (reuse the JS files from BrowserExtension/).")
                Text("The extension connects automatically when the native app is running.")
                    .font(.caption)
                Button("OK") { showExtensionHelp = false }
            }
            .padding()
            .frame(width: 380)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let action: () -> Void
    let description: String

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundColor(granted ? .green : .orange)
                .font(.title3)

            VStack(alignment: .leading) {
                HStack {
                    Text(title)
                        .font(.headline)
                    if !granted {
                        Button("Grant") { action() }
                            .buttonStyle(.borderless)
                            .foregroundColor(.blue)
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}
