import Foundation

/// A database Brandon has chosen to expose in Arthur. Baserow's token auth
/// can't list a workspace's databases (that endpoint is JWT-only — confirmed
/// against Baserow's docs while building the sibling Chrome extension), so
/// this list is hand-configured in Settings rather than fetched.
public struct BaserowDatabase: Codable, Identifiable, Hashable {
    public var id: Int
    public var name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

public struct BaserowTable: Codable, Identifiable, Hashable {
    public var id: Int
    public var name: String
    public var databaseId: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case databaseId = "database_id"
    }
}

public struct BaserowSelectOption: Codable, Hashable {
    public var value: String
}

public struct BaserowField: Codable, Identifiable, Hashable {
    public var id: Int
    public var name: String
    public var type: String
    public var readOnly: Bool
    /// Baserow's designated title field for a table (exactly one per
    /// table) — used by search results to show a sensible title instead of
    /// an arbitrary field.
    public var primary: Bool
    public var selectOptions: [BaserowSelectOption]?
    public var dateIncludeTime: Bool?
    public var maxValue: Int?
    public var numberDecimalPlaces: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, type, primary
        case readOnly = "read_only"
        case selectOptions = "select_options"
        case dateIncludeTime = "date_include_time"
        case maxValue = "max_value"
        case numberDecimalPlaces = "number_decimal_places"
    }

    /// Never settable on row create — hidden from the capture form. Same
    /// list as the Chrome extension's READ_ONLY_TYPES.
    public static let readOnlyTypes: Set<String> = [
        "formula", "lookup", "created_on", "created_by", "last_modified",
        "last_modified_by", "count", "rollup", "autonumber", "uuid", "button", "ai"
    ]

    /// Types the capture form doesn't build an input for (too complex for a
    /// quick-push form) — listed as skipped, not silently dropped. Same list
    /// as the extension's UNSUPPORTED_TYPES.
    public static let unsupportedTypes: Set<String> = ["file", "link_to_table", "password"]

    public var isWritable: Bool {
        !readOnly && !Self.readOnlyTypes.contains(type) && !Self.unsupportedTypes.contains(type)
    }
}

/// A single row's raw field values, keyed by field name. Not Codable — rows
/// have an arbitrary per-table schema, so there's no fixed shape to decode
/// into; callers pull known field names (configured in Settings, e.g. the
/// Seneca "Quote"/"Author" field names) out of `fields` themselves.
public struct BaserowRow: Identifiable {
    public let id: Int
    public let fields: [String: Any]
}
