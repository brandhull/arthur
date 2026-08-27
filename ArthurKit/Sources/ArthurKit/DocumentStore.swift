import Foundation
import Combine

/// Caches the space's documents on disk so the floating-capture picker is
/// instant, refreshing in the background — trimmed single-space version of
/// craft-quick-capture's DocumentStore (no collections/multi-space, Arthur
/// only pushes free-form text to pages).
///
/// Lives in ArthurKit (moved from the App target) so both the main app and
/// ArthurBar's menu-bar Quick Capture share the exact same search/recents
/// logic and, since both write to the same shared `Config.supportDir`
/// files, the exact same on-disk cache and recents list too — using Quick
/// Capture from either one keeps the other's suggestions in sync.
@MainActor
public final class DocumentStore: ObservableObject {
    @Published public var documents: [CraftDocument] = []
    @Published public var recentIds: [String] = []
    @Published public var isRefreshing = false

    private var lastFetch: Date?
    private var cacheFile: URL { Config.supportDir.appendingPathComponent("documents.json") }
    private var recentsFile: URL { Config.supportDir.appendingPathComponent("recents.json") }

    private struct Cache: Codable { var fetchedAt: Date; var docs: [CraftDocument] }

    public init() {
        if let data = try? Data(contentsOf: cacheFile),
           let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            documents = cache.docs
            lastFetch = cache.fetchedAt
        }
        if let data = try? Data(contentsOf: recentsFile),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            recentIds = ids
        }
    }

    public func refreshIfStale(craftLink: String, maxAge: TimeInterval = 15 * 60) {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < maxAge, !documents.isEmpty { return }
        refresh(craftLink: craftLink)
    }

    public func refresh(craftLink: String) {
        guard !isRefreshing, !craftLink.isEmpty else { return }
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            do {
                let docs = try await CraftClient(url: craftLink).listAllDocuments()
                documents = docs
                lastFetch = Date()
                let cache = Cache(fetchedAt: Date(), docs: docs)
                if let data = try? JSONEncoder().encode(cache) {
                    try? data.write(to: cacheFile)
                }
            } catch {
                // Stale cache is still useful; just leave it in place.
            }
        }
    }

    public func markUsed(_ id: String) {
        recentIds.removeAll { $0 == id }
        recentIds.insert(id, at: 0)
        recentIds = Array(recentIds.prefix(8))
        if let data = try? JSONEncoder().encode(recentIds) {
            try? data.write(to: recentsFile)
        }
    }

    /// Case-insensitive, every space-separated token must appear in the title
    /// or folder. Ranking: title prefix beats title word-start beats any match.
    public func search(_ query: String, limit: Int = 8) -> [CraftDocument] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            let recents = recentIds.compactMap { id in documents.first { $0.id == id } }
            return recents.isEmpty ? Array(documents.prefix(limit)) : Array(recents.prefix(limit))
        }
        let tokens = q.split(separator: " ").map(String.init)
        var scored: [(doc: CraftDocument, score: Int)] = []
        for doc in documents {
            let t = doc.title.lowercased()
            let hay = t + " " + (doc.folder?.lowercased() ?? "")
            guard tokens.allSatisfy({ hay.contains($0) }) else { continue }
            if t.hasPrefix(q) { scored.append((doc, 0)) }
            else if t.contains(" \(q)") { scored.append((doc, 1)) }
            else { scored.append((doc, 2)) }
        }
        return scored.sorted { ($0.score, $0.doc.title) < ($1.score, $1.doc.title) }
            .prefix(limit).map(\.doc)
    }
}
