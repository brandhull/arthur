import Foundation

/// One captured "bit" of text — a row in the Baserow table that also backs
/// the standalone Bits web app. The table has a long-text `Text` field, a
/// "Created on" `Created` field, and a boolean `Archived` field.
public struct Bit: Identifiable, Equatable {
    public let id: Int
    public var text: String
    /// Baserow's `Created` value: a date-only ("2026-09-28") or full ISO
    /// timestamp, depending on how the field is configured.
    public let created: String?

    public init(id: Int, text: String, created: String?) {
        self.id = id
        self.text = text
        self.created = created
    }

    /// Same rules as the Bits web app's fmtDate: time-of-day for today, "Sep
    /// 28" for older dates (with the time when the field includes one), and
    /// just "Today" when the field is date-only.
    public var displayDate: String {
        guard let created, !created.isEmpty else { return "" }
        let calendar = Calendar.current
        if !created.contains("T") {
            let parts = created.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                  let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
            else { return created }
            return calendar.isDateInToday(date) ? "Today" : date.formatted(.dateTime.month(.abbreviated).day())
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: created) ?? ISO8601DateFormatter().date(from: created) else { return created }
        let time = date.formatted(.dateTime.hour().minute())
        if calendar.isDateInToday(date) { return time }
        return date.formatted(.dateTime.month(.abbreviated).day()) + " " + time
    }
}

/// Reads and writes Bits straight against Baserow (no Cloudflare proxy, no
/// PIN) — Arthur already holds a Baserow token for Seneca and Quick Capture.
public struct BitsClient {
    private static let textField = "Text"
    private static let createdField = "Created"
    private static let archivedField = "Archived"

    public let tableId: Int
    private let client: BaserowClient

    public init(token: String, tableId: Int) {
        self.tableId = tableId
        self.client = BaserowClient(token: token)
    }

    /// Newest first. `archived` picks which side of the Archived checkbox to
    /// list. Baserow can only order by real fields, and Created may be
    /// date-only, so rows are re-sorted by id to get newest-first within a
    /// day — same approach as the Bits web app's server.
    public func list(archived: Bool, limit: Int = 50) async throws -> [Bit] {
        let query = "order_by=-\(Self.createdField)&filter__\(Self.archivedField)__boolean=\(archived)"
        let rows = try await client.listRows(tableId: tableId, size: limit, extraQuery: query)
        return rows
            .map { Bit(id: $0.id, text: $0.fields[Self.textField] as? String ?? "", created: $0.fields[Self.createdField] as? String) }
            .sorted { $0.id > $1.id }
    }

    public func add(text: String) async throws {
        try await client.createRow(tableId: tableId, fields: [Self.textField: text])
    }

    public func update(id: Int, text: String) async throws {
        try await client.updateRow(tableId: tableId, rowId: id, fields: [Self.textField: text])
    }

    public func setArchived(id: Int, archived: Bool) async throws {
        try await client.updateRow(tableId: tableId, rowId: id, fields: [Self.archivedField: archived])
    }

    public func delete(id: Int) async throws {
        try await client.deleteRow(tableId: tableId, rowId: id)
    }
}
