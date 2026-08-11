import Foundation

public enum BaserowError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "No Baserow API token set. Open Settings to paste your Baserow token."
        case .http(let code, let detail): return "Baserow API returned \(code): \(detail)"
        case .badResponse: return "Unexpected response from Baserow"
        }
    }
}

/// Minimal Baserow REST client, ported from the baserow-quick-push Chrome
/// extension's background.js. Database-token auth (not JWT), talking
/// directly to api.baserow.io — no CORS concerns since this runs in a native
/// app rather than a browser extension.
public struct BaserowClient {
    public let apiURL: String
    public let token: String

    public init(apiURL: String = "https://api.baserow.io", token: String) {
        self.apiURL = apiURL.hasSuffix("/") ? String(apiURL.dropLast()) : apiURL
        self.token = token
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard !token.isEmpty else { throw BaserowError.notConfigured }
        guard let url = URL(string: "\(apiURL)\(path)") else { throw BaserowError.badResponse }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let detail = String(decoding: data, as: UTF8.self)
            throw BaserowError.http(http.statusCode, String(detail.prefix(400)))
        }
        return data
    }

    /// Database tokens can't call `/api/database/tables/database/{id}/`
    /// (JWT-only) — confirmed against Baserow's docs while building the
    /// sibling Chrome extension. `all-tables/` accepts a token but returns
    /// every table across every database the token can see, so this filters
    /// client-side.
    public func listTables(databaseId: Int) async throws -> [BaserowTable] {
        let data = try await request("/api/database/tables/all-tables/")
        let all = try JSONDecoder().decode([BaserowTable].self, from: data)
        return all.filter { $0.databaseId == databaseId }
    }

    public func listFields(tableId: Int) async throws -> [BaserowField] {
        let data = try await request("/api/database/fields/table/\(tableId)/")
        return try JSONDecoder().decode([BaserowField].self, from: data)
    }

    public func createRow(tableId: Int, fields: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: fields)
        _ = try await request("/api/database/rows/table/\(tableId)/?user_field_names=true", method: "POST", body: body)
    }

    /// Rows have an arbitrary, per-table schema, so unlike `listFields`
    /// there's no fixed Codable shape to decode into — this hands back the
    /// raw per-field values keyed by field name (`user_field_names=true`)
    /// for the caller to pull known field names out of. `size` caps at
    /// Baserow's own page-size ceiling (200); fine for a commonplace-book
    /// table, not built to paginate through thousands of rows.
    ///
    /// `search`, when non-nil/non-empty, adds Baserow's own `search=` query
    /// param — the row-list endpoint filters server-side against every
    /// searchable field in the table. There's no equivalent *cross-table*
    /// search in Baserow's API; a caller wanting to search several tables
    /// has to call this once per table.
    ///
    /// No `orderBy` param — tried `order_by=-id` for Search Baserow's
    /// "most recent 5" fallback, but Baserow rejects ordering by the
    /// synthetic "id" column once `user_field_names=true` is set
    /// (`ERROR_ORDER_BY_FIELD_NOT_FOUND`, confirmed live), and there's no
    /// field guaranteed to exist on every table to order by instead.
    /// Callers wanting "most recent" sort the default (unordered) response
    /// client-side.
    public func listRows(tableId: Int, search: String? = nil, size: Int = 200) async throws -> [BaserowRow] {
        var path = "/api/database/rows/table/\(tableId)/?user_field_names=true&size=\(size)"
        if let search, !search.isEmpty {
            let encoded = search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? search
            path += "&search=\(encoded)"
        }
        let data = try await request(path)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = obj["results"] as? [[String: Any]]
        else { throw BaserowError.badResponse }
        return results.compactMap { row in
            guard let id = row["id"] as? Int else { return nil }
            return BaserowRow(id: id, fields: row)
        }
    }

    /// Patches a single field on an existing row — used to stamp a
    /// "last shown" date after a quote is displayed, without touching any
    /// of the row's other fields.
    public func updateRowField(tableId: Int, rowId: Int, fieldName: String, value: Any) async throws {
        let body = try JSONSerialization.data(withJSONObject: [fieldName: value])
        _ = try await request("/api/database/rows/table/\(tableId)/\(rowId)/?user_field_names=true", method: "PATCH", body: body)
    }
}
