import Foundation

/// Remembers the last-known table list per database and field list per table,
/// on disk, so the Baserow pickers can show something instantly and refresh
/// behind it (stale-while-revalidate) instead of waiting on the network every
/// time a database or table is picked. Nothing here is authoritative — every
/// cached value is replaced as soon as a fresh fetch succeeds.
public actor BaserowCache {
    public static let shared = BaserowCache()
    private init() {}

    private struct Store: Codable {
        var tables: [Int: [BaserowTable]] = [:]
        var fields: [Int: [BaserowField]] = [:]
    }

    private var store: Store?

    private var fileURL: URL { Config.supportDir.appendingPathComponent("baserowCache.json") }

    private func loaded() -> Store {
        if let store { return store }
        let value = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(Store.self, from: $0) } ?? Store()
        store = value
        return value
    }

    private func persist(_ value: Store) {
        store = value
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public func tables(for databaseId: Int) -> [BaserowTable]? { loaded().tables[databaseId] }
    public func fields(for tableId: Int) -> [BaserowField]? { loaded().fields[tableId] }

    public func setTables(_ tables: [BaserowTable], for databaseId: Int) {
        var value = loaded()
        guard value.tables[databaseId] != tables else { return }
        value.tables[databaseId] = tables
        persist(value)
    }

    public func setFields(_ fields: [BaserowField], for tableId: Int) {
        var value = loaded()
        guard value.fields[tableId] != fields else { return }
        value.fields[tableId] = fields
        persist(value)
    }
}
