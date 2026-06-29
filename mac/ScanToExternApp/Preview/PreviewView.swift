import SwiftUI

struct PreviewView: View {
    @State var text: String
    @State var isEditing: Bool = false
    @State private var dismissProgress: Double = 1.0
    @State private var autoTimer: Timer?
    @State private var didFire: Bool = false   // guards against double-inject

    var onInject: (String) -> Void
    var onDiscard: () -> Void

    private var autoDismissSeconds: Double {
        SettingsStore.shared.previewTimeout
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "doc.text.viewfinder")
                    .foregroundColor(.blue)
                Text("Scanned Text")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()

                // Progress bar for auto dismiss
                ProgressView(value: dismissProgress, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(width: 80)
            }

            if isEditing {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 80, maxHeight: 140)
                    .border(Color.secondary.opacity(0.3))
            } else {
                Text(text)
                    .font(.body)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.6))
                    .cornerRadius(6)
            }

            HStack {
                Button(role: .destructive) {
                    fireOnce { onDiscard() }
                } label: {
                    Text("Discard")
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button {
                    isEditing.toggle()
                    // Pause auto-dismiss while editing so we don't inject mid-edit.
                    if isEditing {
                        cancelTimer()
                    } else {
                        startAutoDismissTimer()
                    }
                } label: {
                    Text(isEditing ? "Done" : "Edit")
                }

                Button {
                    fireOnce { onInject(text) }
                } label: {
                    Text("Inject")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(radius: 16)
        .onAppear {
            startAutoDismissTimer()
        }
        .onDisappear {
            cancelTimer()
        }
    }

    /// Ensures inject/discard happens at most once (button click OR timeout, never both).
    private func fireOnce(_ action: () -> Void) {
        guard !didFire else { return }
        didFire = true
        cancelTimer()
        action()
    }

    private func cancelTimer() {
        autoTimer?.invalidate()
        autoTimer = nil
    }

    private func startAutoDismissTimer() {
        cancelTimer()
        dismissProgress = 1.0
        let total = max(autoDismissSeconds, 0.5)
        autoTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            dismissProgress -= (0.05 / total)
            if dismissProgress <= 0 {
                timer.invalidate()
                // On timeout, auto-inject the (possibly edited) text — once.
                fireOnce { onInject(text) }
            }
        }
    }
}
