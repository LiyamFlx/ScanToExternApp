import Foundation

/// Orchestrates on-device Foundation Models (when available) + opt-in Claude.
/// Used from preview / history re-inject path.
///
/// If a processing step fails (bad API key, offline, model unavailable), we log the
/// error and return the original text — the user always gets their scan; AI is
/// enhancement, not gatekeeping.
final class AIProcessor: ObservableObject {
    static let shared = AIProcessor()

    @Published var mode: ProcessingMode = .off
    @Published var customInstruction: String = ""

    /// Last non-fatal AI error surfaced to the UI (so the popover can show a hint like
    /// "Claude API key rejected"). Cleared on the next successful process().
    @Published var lastError: String?

    enum ProcessingMode: String, CaseIterable {
        case off = "Off"
        case correct = "Auto-correct OCR"
        case translate = "Translate"
        case summarize = "Summarize"
        case custom = "Custom instruction"
    }

    func process(_ text: String) async -> String {
        let currentMode = SettingsStore.shared.aiMode

        switch currentMode {
        case "off":
            await clearError()
            return text

        case "correct":
            // Foundation Models is a stub on our current SDK — it does light local cleanup.
            // Once macOS 15.1+ SDK is available we swap the body of FoundationModelProcessor
            // for a real LanguageModelSession call. Not silent — the return is deterministic.
            if #available(macOS 15.1, *) {
                let out = await FoundationModelProcessor().process(text, mode: .correct)
                await clearError()
                return out
            }
            await setError("Auto-correct needs macOS 15.1 (Apple Intelligence). Returning raw scan.")
            return text

        case "translate":
            let lang = SettingsStore.shared.targetLanguage
            if #available(macOS 15.1, *) {
                let out = await FoundationModelProcessor().process(text, mode: .translate(to: lang))
                await clearError()
                return out
            }
            await setError("Translate needs macOS 15.1 (Apple Intelligence). Returning raw scan.")
            return text

        case "summarize", "custom":
            let key = SettingsStore.shared.claudeAPIKey
            guard !key.isEmpty else {
                await setError("Claude API key not set (Settings → AI). Returning raw scan.")
                return text
            }
            let instruction = (currentMode == "custom" && !customInstruction.isEmpty)
                ? customInstruction
                : "Summarize the following text in one sentence:"
            do {
                let out = try await ClaudeProcessor(apiKey: key).process(text, instruction: instruction)
                await clearError()
                return out
            } catch {
                let msg = "Claude call failed: \((error as NSError).localizedDescription). Returning raw scan."
                print("[AI] \(msg)")
                await setError(msg)
                return text
            }

        default:
            await clearError()
            return text
        }
    }

    @MainActor private func setError(_ msg: String) { lastError = msg }
    @MainActor private func clearError() { lastError = nil }
}
