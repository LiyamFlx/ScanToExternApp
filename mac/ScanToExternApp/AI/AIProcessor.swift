import Foundation

/// Orchestrates on-device Foundation Models (when available) + opt-in Claude.
/// Used from preview / history re-inject path.
final class AIProcessor: ObservableObject {
    static let shared = AIProcessor()

    @Published var mode: ProcessingMode = .off
    @Published var customInstruction: String = ""

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
            return text

        case "correct":
            if #available(macOS 15.1, *) {
                return await (try? FoundationModelProcessor().process(text, mode: .correct)) ?? text
            }
            return text

        case "translate":
            let lang = SettingsStore.shared.targetLanguage
            if #available(macOS 15.1, *) {
                return await (try? FoundationModelProcessor().process(text, mode: .translate(to: lang))) ?? text
            }
            return text

        case "summarize", "custom":
            let key = SettingsStore.shared.claudeAPIKey
            guard !key.isEmpty else { return text }
            let instruction = (currentMode == "custom" && !customInstruction.isEmpty) ? customInstruction : "Summarize the following text in one sentence:"
            return (try? await ClaudeProcessor(apiKey: key).process(text, instruction: instruction)) ?? text

        default:
            return text
        }
    }
}
