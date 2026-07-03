import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var controller: MenuBarController
    @ObservedObject private var registry = DeviceRegistry.shared
    @ObservedObject private var ai = AIProcessor.shared

    @State private var lastScanned: String = "No scans yet. Scan with your pen to start."
    @State private var aiEnabled: Bool = SettingsStore.shared.aiMode != "off"

    @State private var showingHistory = false
    @State private var showingSettings = false
    @State private var showingDevices = false
    @State private var showingOnboarding = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

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
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "5.0")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 4)

            Divider()

            // Status indicator (driven by DeviceRegistry — rich states: scanning, connecting, connected, reconnecting, failed)
            Button {
                showingDevices = true
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text(statusText)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    Spacer()
                    if let b = registry.battery {
                        Text("\(b)%").font(.caption).foregroundColor(.secondary)
                    }
                    Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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

            // AI error banner — surfaces the last AI processing failure so users know
            // WHY their scanned text wasn't transformed (bad Claude key, offline, etc.).
            if let err = ai.lastError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                }
            }

            Spacer(minLength: 16)

            // Controls
            HStack(spacing: 8) {
                Button {
                    showingDevices = true
                } label: {
                    Label("Devices", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.bordered)

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
        .onReceive(controller.$lastScanPreview) { preview in
            if !preview.isEmpty { lastScanned = preview }
        }
        .sheet(isPresented: $showingDevices) {
            DevicesView()
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingOnboarding) {
            PermissionsOnboardingView()
        }
        .onAppear {
            if !hasSeenOnboarding && !PermissionsManager.shared.allCriticalPermissionsGranted {
                // Auto show once on first run if permissions missing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showingOnboarding = true
                    hasSeenOnboarding = true
                }
            }
        }
    }

    // MARK: - Status label + color (derived from DeviceRegistry.status)

    private var statusText: String {
        switch registry.status {
        case .bluetoothOff:          return "Bluetooth off — tap to fix"
        case .bluetoothUnauthorized: return "Bluetooth permission denied"
        case .idle:                  return "No device paired — tap to pick one"
        case .scanning:              return "Scanning for scanners…"
        case .connecting(let n):     return "Connecting to \(n)…"
        case .connected(let n, _):   return "Connected: \(n)"
        case .reconnecting(let n):   return "Reconnecting to \(n)…"
        case .failed:                return "Error — tap for details"
        }
    }

    private var statusColor: Color {
        switch registry.status {
        case .connected: return .green
        case .connecting, .reconnecting, .scanning: return .orange
        case .bluetoothOff, .bluetoothUnauthorized, .failed: return .red
        case .idle: return .gray
        }
    }
}

// Full implementations live in ../History/HistoryView.swift and ../Settings/SettingsView.swift
// (included via the SPM target / Xcode sources)
