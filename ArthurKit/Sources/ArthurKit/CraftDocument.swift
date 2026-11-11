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
    /// "Parent / Child" display path; equals `name` for top-level folders.
    public let path: String

    public init(id: String, name: String, path: String? = nil) {
        self.id = id
        self.name = name
        self.path = path ?? name
    }
}
