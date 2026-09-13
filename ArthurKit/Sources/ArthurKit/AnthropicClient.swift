import Foundation

public enum AnthropicError: LocalizedError {
    case notConfigured
    case http(Int)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "No Anthropic API key set. Open Settings to paste your API key."
        case .http(let code): return "Anthropic API returned HTTP \(code)"
        case .badResponse: return "Unexpected response from Anthropic"
        }
    }
}

/// Minimal wrapper around Anthropic's Messages API — the answer-synthesis
/// step behind "Search Craft": Craft's own `search` finds candidate
/// documents/blocks (CraftClient.search), then this asks Claude to pull the
/// actual answer out of their fetched content, rather than just handing
/// Brandon a pile of matching documents to read through himself.
public struct AnthropicClient {
    public let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Haiku, not Sonnet — this is straightforward extraction ("find the
    /// fact in this text"), not complex reasoning, and Search Craft is
    /// meant to be a fast/cheap everyday lookup, not an occasional
    /// heavyweight query.
    public func ask(question: String, context: String, model: String = "claude-haiku-4-5-20251001") async throws -> String {
        guard !apiKey.isEmpty else { throw AnthropicError.notConfigured }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let prompt = """
        Answer the question using only the notes below. Be concise — give just the direct answer, no preamble or restating the question. If the notes don't actually contain the answer, say so plainly rather than guessing. Plain text only — no markdown (no **bold**, no bullet points, no headers); the answer is displayed as plain, unformatted text.

        Question: \(question)

        Notes:
        \(context)
        """
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 300,
            "messages": [["role": "user", "content": prompt]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AnthropicError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw AnthropicError.http(http.statusCode) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw AnthropicError.badResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
