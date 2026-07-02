import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared

    var body: some View {
        TabView {
            // General
            Form {
                Toggle("Show preview toast", isOn: $settings.previewEnabled)
                Slider(value: $settings.previewTimeout, in: 1...15, step: 0.5) {
                    Text("Preview timeout: \(settings.previewTimeout, specifier: "%.1f")s")
                }
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Text(LaunchAtLoginManager.isEnabled() ? "Currently registered with the system" : "Not currently registered")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Preferred injection", selection: $settings.injectionMethod) {
                    Text("Accessibility (AX)").tag("ax")
                    Text("Clipboard fallback only").tag("clipboard")
                }
            }
            .tabItem { Label("General", systemImage: "gear") }

            // AI
            Form {
                Picker("AI Mode", selection: $settings.aiMode) {
                    Text("Off").tag("off")
                    Text("Auto-correct OCR").tag("correct")
                    Text("Translate").tag("translate")
                    Text("Summarize").tag("summarize")
                    Text("Custom instruction").tag("custom")
                }
                if settings.aiMode == "translate" {
                    TextField("Target language", text: $settings.targetLanguage)
                }
                SecureField("Anthropic Claude API Key (opt-in)", text: $settings.claudeAPIKey)
                    .textContentType(.password)
                Text("Stored securely in Keychain (com.topscan.ScanToExternApp).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .tabItem { Label("AI", systemImage: "brain") }

            // History
            Form {
                Toggle("Enable scan history", isOn: $settings.historyEnabled)
                Stepper("Max records: \(settings.historyLimit)", value: $settings.historyLimit, in: 10...2000, step: 50)
                Button("Clear History Now") {
                    try? ScanHistoryStore.shared.deleteAll()
                }
            }
            .tabItem { Label("History", systemImage: "clock") }

            // Device
            VStack(alignment: .leading, spacing: 10) {
                Text("Hardware")
                    .font(.headline)
                Text("Pair with your Scanmarker from the Devices panel in the menubar popover — pick a scanner from the Nearby list, or unplug/replug a USB scanner to add it.")
                    .font(.caption).foregroundColor(.secondary)
                Toggle("Prefer Bluetooth over USB when both connected", isOn: $settings.preferBluetooth)
                Button("Rescan for devices") {
                    HardwareManager.shared.forceRescan()
                }
            }
            .padding(.top, 4)
            .tabItem { Label("Device", systemImage: "antenna.radiowaves.left.and.right") }
        }
        .frame(width: 480, height: 380)
        .padding()
    }
}
