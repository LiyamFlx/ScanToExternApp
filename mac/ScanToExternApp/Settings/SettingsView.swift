import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gear") }

            aiTab
                .tabItem { Label("AI", systemImage: "brain") }

            history
                .tabItem { Label("History", systemImage: "clock") }

            device
                .tabItem { Label("Device", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .frame(width: 520, height: 420)
        .padding()
    }

    // MARK: - General

    /// Uses a plain VStack instead of SwiftUI's `Form` because Form on macOS 13/14 lays out
    /// controls as a 2-column grid where labels and controls can visually collide with each
    /// other (the previous version had the timeout slider overlapping the "Show preview toast"
    /// checkbox). A vertical stack + labeled rows renders predictably.
    private var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Show preview toast before injecting", isOn: $settings.previewEnabled)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Preview timeout")
                    Spacer()
                    Text("\(settings.previewTimeout, specifier: "%.1f") s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Slider(value: $settings.previewTimeout, in: 1...15, step: 0.5)
            }

            Toggle("Launch at login", isOn: $settings.launchAtLogin)
            Text(LaunchAtLoginManager.isEnabled()
                 ? "Currently registered with the system"
                 : "Not currently registered")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Text("Preferred injection")
                Picker("", selection: $settings.injectionMethod) {
                    Text("Accessibility (AX)").tag("ax")
                    Text("Clipboard fallback only").tag("clipboard")
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - AI

    private var aiTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Scanmarker cloud OCR account — the pen sends compressed image bytes; the
            // vendor's server does the OCR. Without a registered account email + paired
            // pen serial, the service returns empty text.
            VStack(alignment: .leading, spacing: 4) {
                Text("Scanmarker account email")
                    .font(.headline)
                TextField("you@example.com", text: $settings.scanmarkerEmail)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                Text("Required for real OCR — the ScanMarker cloud service returns empty text for anonymous callers. Pen serial is read automatically over BLE.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Text("AI Mode (post-processing)")
                Picker("", selection: $settings.aiMode) {
                    Text("Off").tag("off")
                    Text("Auto-correct OCR").tag("correct")
                    Text("Translate").tag("translate")
                    Text("Summarize").tag("summarize")
                    Text("Custom instruction").tag("custom")
                }
                .labelsHidden()
                .frame(maxWidth: 280)
            }

            if settings.aiMode == "translate" {
                HStack {
                    Text("Target language")
                    TextField("English", text: $settings.targetLanguage)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Anthropic Claude API key (for AI post-processing)")
                SecureField("sk-ant-…", text: $settings.claudeAPIKey)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
                Text("Stored securely in Keychain. Only used if AI mode is Summarize/Custom.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - History

    private var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Enable scan history", isOn: $settings.historyEnabled)

            HStack {
                Text("Max records")
                Stepper(value: $settings.historyLimit, in: 10...2000, step: 50) {
                    Text("\(settings.historyLimit)")
                        .font(.body)
                        .frame(minWidth: 60, alignment: .leading)
                }
            }

            Button("Clear history now") {
                do { try ScanHistoryStore.shared.deleteAll() }
                catch { print("[History] Clear failed: \(error)") }
            }
            .foregroundColor(.red)

            Spacer()
        }
        .padding()
    }

    // MARK: - Device

    private var device: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hardware").font(.headline)
            Text("Pair with your Scanmarker from the Devices panel in the menubar popover — pick a scanner from the Nearby list, or plug in a USB scanner.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Prefer Bluetooth over USB when both are connected", isOn: $settings.preferBluetooth)

            Button("Rescan for devices") {
                HardwareManager.shared.forceRescan()
            }

            Spacer()
        }
        .padding()
    }
}
