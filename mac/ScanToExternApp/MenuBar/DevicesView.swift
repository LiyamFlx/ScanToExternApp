import SwiftUI

/// In-app Bluetooth / USB device management. Replaces the previous silent
/// auto-connect: the user sees what's nearby, picks a device to pair, and can
/// disconnect or "forget" the paired one.
struct DevicesView: View {
    @ObservedObject private var registry = DeviceRegistry.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            statusBanner

            Divider()

            if let paired = pairedRow {
                pairedSection(paired)
                Divider()
            }

            nearbySection

            Spacer(minLength: 8)
        }
        .padding(14)
        .frame(width: 420, height: 460)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Devices")
                .font(.title2.weight(.semibold))
            Spacer()
            Button {
                registry.requestRefresh()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Status banner

    private var statusBanner: some View {
        HStack(spacing: 8) {
            Circle().fill(bannerColor).frame(width: 10, height: 10)
            Text(bannerText).font(.subheadline)
            Spacer()
            if let b = registry.battery {
                Label("\(b)%", systemImage: "battery.100")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var bannerColor: Color {
        switch registry.status {
        case .connected: return .green
        case .connecting, .reconnecting, .scanning: return .orange
        case .bluetoothOff, .bluetoothUnauthorized, .failed: return .red
        case .idle: return .gray
        }
    }

    private var bannerText: String {
        switch registry.status {
        case .bluetoothOff:         return "Bluetooth is OFF — turn it on in System Settings"
        case .bluetoothUnauthorized: return "Bluetooth permission denied — enable it in Privacy & Security"
        case .idle:                 return "Idle — pick a device below to connect"
        case .scanning:             return "Scanning for nearby scanners…"
        case .connecting(let n):    return "Connecting to \(n)…"
        case .connected(let n, _):  return "Connected to \(n)"
        case .reconnecting(let n):  return "Reconnecting to \(n)…"
        case .failed(let reason):   return "Error: \(reason)"
        }
    }

    // MARK: - Sections

    private var pairedRow: DeviceRegistry.Device? {
        guard let id = registry.preferredDeviceID else { return nil }
        return registry.discovered.first(where: { $0.id == id })
    }

    @ViewBuilder
    private func pairedSection(_ dev: DeviceRegistry.Device) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Paired")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            HStack {
                deviceIcon(dev.kind)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dev.name).font(.body.weight(.medium))
                    HStack(spacing: 8) {
                        rssiIndicator(dev.rssi)
                        if let b = registry.battery {
                            Text("• Battery \(b)%").font(.caption).foregroundColor(.secondary)
                        }
                        if case .connected = registry.status {
                            Text("• Live").font(.caption).foregroundColor(.green)
                        }
                    }
                }
                Spacer()
                Button("Disconnect") { registry.requestDisconnect() }
                    .buttonStyle(.bordered)
                Button("Forget") { registry.requestForget() }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Nearby")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if case .scanning = registry.status {
                    ProgressView().controlSize(.small)
                }
            }

            let nearby = registry.discovered.filter { $0.id != registry.preferredDeviceID }
            if nearby.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(nearby, id: \.id) { dev in
                            nearbyRow(dev)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        HStack {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundColor(.secondary)
            Text("No scanners visible yet. Make sure Bluetooth is on and the Scanmarker is powered up, or plug it in via USB.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func nearbyRow(_ dev: DeviceRegistry.Device) -> some View {
        HStack {
            deviceIcon(dev.kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(dev.name).font(.body)
                rssiIndicator(dev.rssi)
            }
            Spacer()
            Button("Connect") { registry.requestConnect(to: dev.id) }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
        }
        .padding(6)
    }

    private var isBusy: Bool {
        if case .connecting = registry.status { return true }
        if case .reconnecting = registry.status { return true }
        return false
    }

    // MARK: - Small helpers

    @ViewBuilder
    private func deviceIcon(_ kind: DeviceRegistry.Kind) -> some View {
        switch kind {
        case .bluetooth:
            Image(systemName: "cable.connector").foregroundColor(.blue)
        case .usb:
            Image(systemName: "cable.coaxial").foregroundColor(.gray)
        }
    }

    /// 4-bar RSSI indicator. RSSI is typically -100 (very weak) to -30 (very strong).
    /// Bars are cosmetic — the exact mapping doesn't matter, only the ordering.
    @ViewBuilder
    private func rssiIndicator(_ rssi: Int?) -> some View {
        if let rssi = rssi {
            let bars = rssiBars(rssi)
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < bars ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: 4, height: CGFloat(4 + i * 3))
                }
                Text("\(rssi) dBm").font(.caption2).foregroundColor(.secondary)
            }
        } else {
            Text("USB link").font(.caption).foregroundColor(.secondary)
        }
    }

    private func rssiBars(_ rssi: Int) -> Int {
        switch rssi {
        case ..<(-90): return 1
        case -90 ..< -75: return 2
        case -75 ..< -60: return 3
        default: return 4
        }
    }
}
