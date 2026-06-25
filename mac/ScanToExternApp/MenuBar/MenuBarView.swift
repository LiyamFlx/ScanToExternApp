import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var controller: MenuBarController

    @State private var connectionStatus: String = "Disconnected"
    @State private var lastScanned: String = "No scans yet. Scan with your pen to start."
    @State private var deviceInfo: String = "No device connected"
    @State private var battery: Int? = nil
    @State private var aiEnabled: Bool = SettingsStore.shared.aiMode != "off"

    @State private var showingHistory = false
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "doc.text.viewfinder")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("ScanToExternApp")
                    .font(.headline)
                Spacer()
                Text("v5.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 4)

            Divider()

            // Status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text("Status: \(connectionStatus)")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }

            // Last scanned preview
            VStack(alignment: .leading, spacing: 4) {
                Text("Last Scanned")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ScrollView {
                    Text(lastScanned)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                }
                .frame(minHeight: 60, maxHeight: 90)
            }

            // Device
            if connectionStatus != "Disconnected" {
                HStack {
                    VStack(alignment: .leading) {
                        Text(deviceInfo)
                            .font(.caption)
                        if let b = battery {
                            Text("Battery: \(b)%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
            }

            Spacer(minLength: 16)

            // Controls
            HStack(spacing: 8) {
                Button {
                    showingHistory = true
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)

                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)

                Spacer()

                // Debug helper (remove or guard with #if DEBUG in shipping)
                Button("Test Scan") {
                    HardwareManager.shared.simulateScan()
                }
                .buttonStyle(.bordered)
                .font(.caption)

                Toggle("AI", isOn: $aiEnabled)
                    .toggleStyle(.switch)
                    .font(.caption)
                    .onChange(of: aiEnabled) { enabled in
                        SettingsStore.shared.aiMode = enabled ? "correct" : "off"
                    }
            }

            Divider()

            Text("Connect Scanmarker via Bluetooth or USB. Text injects into the focused app or browser tab.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(width: 320, height: 480)
        .onAppear {
            // TODO: Bind to real @Published from HardwareManager + SettingsStore
            // For now skeleton only
            connectionStatus = controller.connectionState.rawValue
        }
        .onReceive(controller.$connectionState) { state in
            connectionStatus = state.rawValue
        }
        .onReceive(controller.$lastScanPreview) { preview in
            if !preview.isEmpty { lastScanned = preview }
        }
        .onReceive(controller.$deviceName) { name in
            if !name.isEmpty { deviceInfo = name }
        }
        .onReceive(controller.$batteryPercent) { b in
            battery = b
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private var statusColor: Color {
        switch connectionStatus {
        case "Connected": return .green
        case "Scanning": return .orange
        default: return .red
        }
    }
}

// Full implementations live in ../History/HistoryView.swift and ../Settings/SettingsView.swift
// (included via the SPM target / Xcode sources)
