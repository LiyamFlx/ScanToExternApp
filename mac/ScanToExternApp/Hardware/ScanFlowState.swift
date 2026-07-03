import Foundation
import Combine

/// Live, user-facing state of the current scan operation. Bound to the popover's
/// "Step 3 — Live scan status" section so the user sees what the app is doing
/// as it happens (receiving bytes → text captured → injecting → done / error).
///
/// This is a *transient* state (it auto-clears back to `.idle` after a few seconds
/// once the flow ends) — distinct from the `DeviceRegistry` link state, which is
/// about the BT/USB connection, and distinct from `HardwareManager.connectionState`.
///
/// Updates are always dispatched onto the main queue so SwiftUI views can bind
/// directly without extra receive-on-main plumbing.
final class ScanFlowState: ObservableObject {
    static let shared = ScanFlowState()

    enum Phase: Equatable {
        case idle                             // "Waiting for pen to scan…"
        case receiving                        // bytes arriving; reassembly not done
        case captured(chars: Int)             // full scan reassembled
        case injecting(target: String)        // pushing into <target> app
        case injected(chars: Int, target: String)   // success — show for a few seconds
        case failed(reason: String)           // non-fatal error, show and reset
    }

    @Published private(set) var phase: Phase = .idle
    /// Preview of the most recent captured text (first ~120 chars, truncated).
    @Published private(set) var lastPreview: String?

    private var idleTimer: Timer?

    private init() {}

    // MARK: - Transitions (called by HardwareManager / InjectionRouter)

    func receiving() {
        set(.receiving)
    }

    func captured(_ text: String) {
        lastPreview = String(text.prefix(120))
        set(.captured(chars: text.count))
    }

    func injecting(into target: String) {
        set(.injecting(target: target))
    }

    /// Success. Stays visible for `visibleSeconds`, then resets to `.idle`.
    func injected(_ chars: Int, into target: String, visibleSeconds: TimeInterval = 3.0) {
        set(.injected(chars: chars, target: target))
        scheduleReturnToIdle(after: visibleSeconds)
    }

    /// Failure. Stays visible for `visibleSeconds`, then resets to `.idle`.
    func failed(_ reason: String, visibleSeconds: TimeInterval = 5.0) {
        set(.failed(reason: reason))
        scheduleReturnToIdle(after: visibleSeconds)
    }

    // MARK: - Internal

    private func set(_ phase: Phase) {
        idleTimer?.invalidate()
        idleTimer = nil
        if Thread.isMainThread {
            self.phase = phase
        } else {
            DispatchQueue.main.async { self.phase = phase }
        }
    }

    private func scheduleReturnToIdle(after seconds: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            self?.idleTimer?.invalidate()
            self?.idleTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
                self?.set(.idle)
            }
        }
    }
}
