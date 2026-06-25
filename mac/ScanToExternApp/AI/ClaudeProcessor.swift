import Foundation

/// Opt-in cloud processor using Anthropic Claude Haiku (claude-haiku-4-5).
/// User must supply API key via Settings.
struct ClaudeProcessor {
    let apiKey: String

    func process(_ text: String, instruction: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NSError(domain: "Claude", code: 401, userInfo: [NSLocalizedDescriptionKey: "No API key"])
        }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": "\(instruction)\n\n\(text)"]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Claude", code: 500, userInfo: [NSLocalizedDescriptionKey: "HTTP error"])
        }

        // Parse { "content": [ {"type":"text", "text": "..."} ] }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let contentArr = json["content"] as? [[String: Any]],
           let first = contentArr.first,
           let result = first["text"] as? String {
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
