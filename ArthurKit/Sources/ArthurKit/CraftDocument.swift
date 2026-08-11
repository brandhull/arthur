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
