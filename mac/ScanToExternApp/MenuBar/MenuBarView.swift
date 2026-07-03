import SwiftUI
import AppKit

/// The main popover UI. Presents the whole scan flow as three clearly-labeled steps
/// with live status, so a first-time user immediately understands what has to happen
/// and what the app is currently doing:
///
///   1. Connect a scanner        — driven by DeviceRegistry.status
///   2. Where scans go            — the currently-focused app the router will target
///   3. Live scan status          — driven by ScanFlowState (idle/receiving/captured/injecting/done/error)
///
/// The bottom row is deliberately compact icon-only (with tooltips) so all four
/// controls fit inside 320 pt without truncating labels.
struct MenuBarView: View {
    @EnvironmentObject var controller: MenuBarController
    @ObservedObject private var registry = DeviceRegistry.shared
    @ObservedObject private var flow = ScanFlowState.shared
    @ObservedObject private var ai = AIProcessor.shared

    @State private var aiEnabled: Bool = SettingsStore.shared.aiMode != "off"

    @State private var showingHistory = false
    @State private var showingSettings = false
    @State private var showingDevices = false
    @State private var showingOnboarding = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()

            step1_ConnectScanner
            Divider()

            step2_TargetApp
            Divider()

            step3_LiveStatus

            if let err = ai.lastError {
                aiErrorBanner(err)
            }

            Spacer(minLength: 6)

            Divider()
            bottomToolbar
        }
        .padding(12)
        .frame(width: 340, height: 520)
        .sheet(isPresented: $showingDevices)     { DevicesView() }
        .sheet(isPresented: $showingHistory)     { HistoryView() }
        .sheet(isPresented: $showingSettings)    { SettingsView() }
        .sheet(isPresented: $showingOnboarding)  { PermissionsOnboardingView() }
        .onAppear {
            if !hasSeenOnboarding && !PermissionsManager.shared.allCriticalPermissionsGranted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showingOnboarding = true
                    hasSeenOnboarding = true
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
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
    }

    // MARK: - Step 1

    private var step1_ConnectScanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            stepLabel(number: 1, title: "Connect a scanner", done: isConnected)
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 10, height: 10)
                Text(step1Text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
                if let b = registry.battery {
                    Text("\(b)%").font(.caption).foregroundColor(.secondary)
                }
            }
            Button {
                showingDevices = true
            } label: {
                Label(isConnected ? "Manage device" : "Connect Now", systemImage: "dot.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }

    private var isConnected: Bool {
        if case .connected = registry.status { return true }
        return false
    }

    private var step1Text: String {
        switch registry.status {
        case .bluetoothOff:          return "Bluetooth is OFF — turn it on in System Settings"
        case .bluetoothUnauthorized: return "Bluetooth permission denied"
        case .idle:                  return "No scanner paired"
        case .scanning:              return "Searching for nearby scanners…"
        case .connecting(let n):     return "Connecting to \(n)…"
        case .connected(let n, _):   return "Connected: \(n)"
        case .reconnecting(let n):   return "Reconnecting to \(n)…"
        case .failed(let r):         return "Error: \(r)"
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

    // MARK: - Step 2

    private var step2_TargetApp: some View {
        VStack(alignment: .leading, spacing: 6) {
            stepLabel(number: 2, title: "Where scans go", done: true)
            HStack(spacing: 8) {
                Image(systemName: "target").foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Follow focused app")
                        .font(.subheadline)
                    Text("Scans land in whatever text field is active when you scan — Notes, Word, Mail, browser tabs (needs the extension).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
    }

    // MARK: - Step 3

    private var step3_LiveStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            stepLabel(number: 3, title: "Live scan status", done: false)
            HStack(spacing: 8) {
                Image(systemName: flowIcon).foregroundColor(flowColor)
                Text(flowText)
                    .font(.subheadline)
                Spacer()
            }
            if let preview = flow.lastPreview, !preview.isEmpty {
                Text(preview)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
            }
        }
    }

    private var flowText: String {
        switch flow.phase {
        case .idle:                          return isConnected ? "Waiting for pen to scan…" : "Connect a scanner to start"
        case .receiving:                     return "Receiving text from scanner…"
        case .captured(let n):               return "Captured \(n) characters"
        case .injecting(let t):              return "Injecting into \(t)…"
        case .injected(let n, let t):        return "✓ Sent \(n) chars to \(t)"
        case .failed(let reason):            return "✗ \(reason)"
        }
    }

    private var flowColor: Color {
        switch flow.phase {
        case .idle:              return .secondary
        case .receiving,
             .captured,
             .injecting:         return .orange
        case .injected:          return .green
        case .failed:            return .red
        }
    }

    private var flowIcon: String {
        switch flow.phase {
        case .idle:         return "waveform"
        case .receiving:    return "waveform.badge.magnifyingglass"
        case .captured:     return "doc.text"
        case .injecting:    return "arrow.right.doc.on.clipboard"
        case .injected:     return "checkmark.circle.fill"
        case .failed:       return "exclamationmark.triangle.fill"
        }
    }

    // MARK: - AI error banner

    private func aiErrorBanner(_ err: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text(err).font(.caption).foregroundColor(.orange)
            Spacer()
        }
    }

    // MARK: - Bottom toolbar (icon-only, tooltipped, fits in 340 pt)

    private var bottomToolbar: some View {
        HStack(spacing: 8) {
            toolbarButton("clock.arrow.circlepath", tooltip: "Scan history") {
                showingHistory = true
            }
            toolbarButton("gearshape", tooltip: "Settings") {
                showingSettings = true
            }
            toolbarButton("shield", tooltip: "Permissions") {
                showingOnboarding = true
            }
            Spacer()
            toolbarButton("play.circle", tooltip: "Test scan (debug)") {
                HardwareManager.shared.simulateScan()
            }
            Toggle("", isOn: $aiEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .help(aiEnabled ? "AI processing: ON" : "AI processing: OFF")
                .onChange(of: aiEnabled) { enabled in
                    SettingsStore.shared.aiMode = enabled ? "correct" : "off"
                }
        }
    }

    @ViewBuilder
    private func toolbarButton(_ systemImage: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: 28, height: 22)
        }
        .buttonStyle(.bordered)
        .help(tooltip)
    }

    // MARK: - Step label

    @ViewBuilder
    private func stepLabel(number: Int, title: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : Color.secondary.opacity(0.25))
                    .frame(width: 18, height: 18)
                if done {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundColor(.white)
                } else {
                    Text("\(number)").font(.caption2.weight(.semibold)).foregroundColor(.primary)
                }
            }
            Text(title).font(.caption.weight(.semibold)).foregroundColor(.secondary)
            Spacer()
        }
    }
}
