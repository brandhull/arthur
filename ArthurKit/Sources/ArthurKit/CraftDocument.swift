import Foundation

/// A document (page) capture destination — ported from craft-quick-capture's
/// CraftDocument, trimmed to Arthur's single-space needs (no multi-space
/// fields, no collections; Arthur only pushes free-form text to pages).
public struct CraftDocument: Codable, Identifiable, Hashable {
    public let id: String      // rootBlockId, usable with `blocks add --id`
    public let title: String
    public var folder: String?

    public init(id: String, title: String, folder: String? = nil) {
        self.id = id
        self.title = title
        self.folder = folder
    }
}

/// A Craft folder — the "Document" quick-add flow's destination (a new page
/// goes *into* a folder, unlike Quick Capture's Craft mode, which appends
/// into an existing CraftDocument).
public struct CraftFolder: Identifiable, Hashable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// One match from CraftClient.search — "Search Craft"'s retrieval step.
/// No title: Craft's real `search` response (confirmed live 2026-09-12)
/// gives back `Document <uuid>` / `Blocks: <uuid>` / a `Match:` text
/// snippet, never a title — the title is fetched separately, per result,
/// via `pageTitleAndMarkdown` once a candidate document is chosen.
public struct CraftSearchResult: Identifiable, Hashable {
    public let id: String      // documentId (rootBlockId), usable with pageMarkdown/clickableLink
    public let snippet: String // the matched block's text, as Craft returned it (bold markers stripped)

    public init(id: String, snippet: String) {
        self.id = id
        self.snippet = snippet
    }
}
