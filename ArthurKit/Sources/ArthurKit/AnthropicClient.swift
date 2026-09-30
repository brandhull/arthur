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
/// step behind "Search Craft".
///
/// Originally this fetched a fixed, pre-guessed set of "top 3" candidate
/// documents (via CraftClient.search's keyword-count ranking) and just asked
/// Claude to extract an answer from whatever that guess handed it — if the
/// guess picked the wrong documents, Claude never had a chance to recover.
/// Replaced with real agentic retrieval: Claude gets tool access to Craft
/// itself (search_craft / list_subpages / read_document, all backed by
/// CraftClient) and drives the lookup the way Brandon would — search, look
/// at what came back, retry with different wording or drill into a
/// sub-page if the first pass didn't have it, stop once it actually has an
/// answer. Bounded to `maxIterations` tool round trips so a stubborn query
/// can't run away on cost/latency — the last iteration always omits tools,
/// forcing a final text answer from whatever's been gathered so far.
public struct AnthropicClient {
    public let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public struct AnswerResult {
        public let answer: String
        public let sourceTitle: String?
        public let sourceId: String?
    }

    private static let tools: [[String: Any]] = [
        [
            "name": "search_craft",
            "description": "Full-text search Brandon's Craft space for a literal word or short phrase. This is EXACT-PHRASE matching, not fuzzy and not a keyword OR — a 3-word query only matches if those exact 3 words appear together verbatim. So: try the most distinctive single word or short exact phrase first, and if it comes back empty, retry with a shorter or different phrasing rather than giving up. Returns up to a few matching blocks, each showing which document it's in (by id) and a short snippet of the matched text.",
            "input_schema": [
                "type": "object",
                "properties": ["query": ["type": "string", "description": "The exact word or phrase to search for."]],
                "required": ["query"]
            ]
        ],
        [
            "name": "list_subpages",
            "description": "Lists the direct sub-pages nested inside a specific Craft document, by that document's id. Use this when the question refers to a sub-page/nested page within a document you've already found (e.g. \"the Notes to Self page inside the Week of ... doc\") — search_craft alone won't surface a sub-page's existence, only matching block content.",
            "input_schema": [
                "type": "object",
                "properties": ["document_id": ["type": "string"]],
                "required": ["document_id"]
            ]
        ],
        [
            "name": "read_document",
            "description": "Reads a specific Craft document's title and full content by its id. Use this once you've identified (via search_craft or list_subpages) which document likely has the answer.",
            "input_schema": [
                "type": "object",
                "properties": ["document_id": ["type": "string"]],
                "required": ["document_id"]
            ]
        ]
    ]

    private static let systemPrompt = """
    You're answering a question about Brandon's own Craft notes, using the search_craft, list_subpages, and read_document tools to look things up yourself — the way Brandon would if he were digging through Craft by hand. Search first, look at what comes back, and search again with different wording (or check sub-pages, or read a promising document's full content) if you haven't actually found the answer yet — don't settle for a first guess that didn't pan out. Once you have a real answer, respond with just that: be concise, plain text only (no markdown — no **bold**, no bullet points, no headers), no preamble, no restating the question. If after genuinely searching you still can't find it, say so plainly rather than guessing.
    """

    /// Haiku, not Sonnet — this is lookup-and-extract, not complex
    /// reasoning, and Search Craft is meant to be a fast/cheap everyday
    /// tool, not an occasional heavyweight query. `maxIterations` bounds it
    /// to a handful of tool round trips even in the worst case (a query
    /// that needs several retries) — still nowhere close to the cost of
    /// fetching Brandon's whole Craft space into context, which the
    /// original design discussion explicitly ruled out.
    public func answer(question: String, craft: CraftClient, model: String = "claude-haiku-4-5-20251001", maxIterations: Int = 6) async throws -> AnswerResult {
        guard !apiKey.isEmpty else { throw AnthropicError.notConfigured }

        var messages: [[String: Any]] = [["role": "user", "content": Self.systemPrompt + "\n\nQuestion: " + question]]
        var sourceTitle: String?
        var sourceId: String?

        for iteration in 0..<maxIterations {
            let includeTools = iteration < maxIterations - 1
            var body: [String: Any] = ["model": model, "max_tokens": 800, "messages": messages]
            if includeTools { body["tools"] = Self.tools }

            let content = try await Self.send(apiKey: apiKey, body: body)
            let toolUses = content.filter { ($0["type"] as? String) == "tool_use" }

            guard !toolUses.isEmpty else {
                let text = content.compactMap { $0["text"] as? String }.joined()
                return AnswerResult(answer: text.trimmingCharacters(in: .whitespacesAndNewlines), sourceTitle: sourceTitle, sourceId: sourceId)
            }

            messages.append(["role": "assistant", "content": content])

            var resultBlocks: [[String: Any]] = []
            for toolUse in toolUses {
                guard let toolUseId = toolUse["id"] as? String, let name = toolUse["name"] as? String else { continue }
                let input = toolUse["input"] as? [String: Any] ?? [:]
                let resultText: String
                do {
                    switch name {
                    case "search_craft":
                        let query = input["query"] as? String ?? ""
                        let results = try await craft.searchOnce(query)
                        resultText = results.isEmpty
                            ? "No matches."
                            : results.map { "Document \($0.id): \($0.snippet)" }.joined(separator: "\n")
                    case "list_subpages":
                        let docId = input["document_id"] as? String ?? ""
                        let pages = try await craft.subPages(of: docId)
                        resultText = pages.isEmpty
                            ? "No sub-pages."
                            : pages.map { "Document \($0.id): \($0.markdown)" }.joined(separator: "\n")
                    case "read_document":
                        let docId = input["document_id"] as? String ?? ""
                        let fetched = try await craft.pageTitleAndMarkdown(rootBlockId: docId)
                        let title = fetched.title.isEmpty ? "Untitled" : fetched.title
                        sourceTitle = title
                        sourceId = docId
                        resultText = "Title: \(title)\n\n\(fetched.markdown)"
                    default:
                        resultText = "Unknown tool: \(name)"
                    }
                } catch {
                    resultText = "Error: \(error.localizedDescription)"
                }
                resultBlocks.append(["type": "tool_result", "tool_use_id": toolUseId, "content": resultText])
            }
            messages.append(["role": "user", "content": resultBlocks])
        }

        // Unreachable in practice — the final iteration always omits
        // `tools`, which forces Claude to return plain text instead of
        // another tool_use, so the early return above always fires first.
        throw AnthropicError.badResponse
    }

    private static func send(apiKey: String, body: [String: Any]) async throws -> [[String: Any]] {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AnthropicError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw AnthropicError.http(http.statusCode) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else {
            throw AnthropicError.badResponse
        }
        return content
    }
}
