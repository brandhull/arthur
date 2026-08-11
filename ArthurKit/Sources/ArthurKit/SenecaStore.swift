import Foundation

/// One cached quote from Brandon's Seneca commonplace-book Baserow table.
/// `id` is the Baserow row id — used to patch "last shown" back onto the
/// right row, and to give SwiftUI's ForEach/animations a stable identity.
public struct SenecaQuote: Codable, Identifiable, Equatable {
    public var id: Int
    public var text: String
    public var author: String?

    public init(id: Int, text: String, author: String?) {
        self.id = id
        self.text = text
        self.author = author
    }
}

/// Manages the splash screen's rotating buffer of Seneca quotes: a small
/// local cache (so cold launch never waits on a network call), refilled in
/// the background, biased toward whatever hasn't been shown recently — same
/// star/`last_shown_at`-style rotation Cannon and Winston already use for
/// their own Review tabs, adapted to read live from Baserow instead of a
/// locally-synced table.
///
/// An actor, not a plain class: SplashView reads `currentQuote()`/calls
/// `advance()` on the main task while a detached background task may be
/// concurrently running `refillIfNeeded` — both touch the same cache file,
/// so actor isolation is what keeps that safe without hand-rolled locking.
public actor SenecaStore {
    public static let shared = SenecaStore()
    private init() {}

    private struct CacheFile: Codable {
        var quotes: [SenecaQuote]
        var index: Int
    }

    /// Field name Arthur writes staleness tracking to — fixed, not
    /// user-configurable like the Quote/Author field names, since Brandon
    /// doesn't read this one, only Arthur does. Must exist as a Date field
    /// on the Seneca table for staleness biasing and repeat-avoidance to
    /// work; if it's missing, refills silently fall back to a plain
    /// shuffle (see refillIfNeeded) rather than failing. Matched
    /// case-insensitively (see resolveFieldName) — a real config had this
    /// added as "Last Shown", not "Last shown", and Baserow's field
    /// matching is exact-case, so a hardcoded literal here silently never
    /// matched anything Brandon actually typed.
    private static let lastShownFieldName = "last shown"

    /// Case-insensitive lookup of a field's real name among a row's keys —
    /// `fields` dictionaries are keyed by Baserow's actual field name
    /// (`user_field_names=true`), so this is how "last shown" finds
    /// whatever casing was actually used ("Last Shown", "last shown", etc.)
    /// without requiring Brandon to match a hardcoded literal exactly.
    private static func resolveFieldName(_ target: String, among keys: some Sequence<String>) -> String? {
        keys.first { $0.caseInsensitiveCompare(target) == .orderedSame }
    }

    /// Below this many unshown quotes left in the buffer, a refill kicks
    /// in. 10 - 3 = a refill roughly every 7 launches/shuffles once warmed
    /// up, rather than hitting Baserow on every single one.
    private static let refillThreshold = 3
    private static let batchSize = 10
    /// Candidate pool pulled before shuffling down to batchSize — gives the
    /// shuffle real variety instead of always landing on the exact same 10
    /// staleness-sorted rows.
    private static let candidatePoolSize = 30

    private var cacheURL: URL { Config.supportDir.appendingPathComponent("senecaCache.json") }

    private func loadCache() -> CacheFile {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(CacheFile.self, from: data)
        else { return CacheFile(quotes: [], index: 0) }
        return cache
    }

    private func saveCache(_ cache: CacheFile) {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL)
        }
    }

    /// Instant, synchronous-feeling (just a small local file read) — what
    /// the splash screen shows immediately on appear. Nil only before the
    /// very first successful refill (e.g. Seneca not configured yet).
    public func currentQuote() -> SenecaQuote? {
        let cache = loadCache()
        guard cache.quotes.indices.contains(cache.index) else { return nil }
        return cache.quotes[cache.index]
    }

    /// Moves the pointer to the next cached quote, so the *next* time the
    /// splash appears — whether that's next cold launch or an immediate
    /// brain-icon tap — a different quote shows. Wraps around if a fresh
    /// batch hasn't arrived yet rather than going empty.
    public func advance() {
        var cache = loadCache()
        guard !cache.quotes.isEmpty else { return }
        cache.index = (cache.index + 1) % cache.quotes.count
        saveCache(cache)
    }

    /// Best-effort background top-up. Silent on any failure — no Baserow
    /// token, Seneca not configured, network error, wrong field names —
    /// the splash just keeps showing whatever's already cached rather than
    /// ever surfacing an error on what's meant to be a quiet, ambient
    /// screen.
    public func refillIfNeeded(config: Config) async {
        let cache = loadCache()
        let remaining = cache.quotes.count - cache.index - 1
        guard remaining < Self.refillThreshold else { return }
        guard config.isBaserowConfigured, let tableId = config.senecaTableId else { return }

        let client = BaserowClient(token: config.baserowToken)
        guard let rows = try? await client.listRows(tableId: tableId) else { return }

        let quoteField = config.senecaQuoteField
        let authorField = config.senecaAuthorField
        // Resolved once per refill from whatever fields the first row
        // actually has — matches "Last Shown", "last shown", etc. Nil
        // (field doesn't exist at all yet) still works fine below: every
        // row's lastShown just ties at "", and the shuffle does the rest.
        let lastShownField = rows.first.flatMap { Self.resolveFieldName(Self.lastShownFieldName, among: $0.fields.keys) }

        let candidates = rows
            .compactMap { row -> (row: BaserowRow, lastShown: String)? in
                guard let text = row.fields[quoteField] as? String,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return nil }
                let lastShown = lastShownField.flatMap { row.fields[$0] as? String } ?? ""
                return (row, lastShown)
            }
            .sorted { $0.lastShown < $1.lastShown }

        let pool = Array(candidates.prefix(Self.candidatePoolSize)).shuffled()
        let picked = Array(pool.prefix(Self.batchSize))
        guard !picked.isEmpty else { return }

        let freshQuotes = picked.map { candidate in
            SenecaQuote(
                id: candidate.row.id,
                text: candidate.row.fields[quoteField] as? String ?? "",
                author: candidate.row.fields[authorField] as? String
            )
        }

        // Keep whatever's left unshown in the current buffer so a refill
        // never cuts a quote off mid-rotation; append the fresh batch after
        // it and reset the pointer to the start of that combined queue.
        let unshown = cache.quotes.indices.contains(cache.index + 1)
            ? Array(cache.quotes[(cache.index + 1)...])
            : []
        saveCache(CacheFile(quotes: unshown + freshQuotes, index: 0))
    }

    /// Fire-and-forget: stamps today's date on the row that was just shown,
    /// so the next refill's staleness ordering reflects it. Swallows
    /// errors — including the expected one where the Seneca table doesn't
    /// have a "Last shown" field yet.
    public func markShown(_ quote: SenecaQuote, config: Config) async {
        guard quote.id > 0, let tableId = config.senecaTableId else { return }
        let client = BaserowClient(token: config.baserowToken)
        // No row payload to resolve the real field name from here (unlike
        // refillIfNeeded), so this asks the table's schema directly — one
        // extra call, but this only runs once per splash display.
        guard let fields = try? await client.listFields(tableId: tableId),
              let lastShownField = Self.resolveFieldName(Self.lastShownFieldName, among: fields.map(\.name))
        else { return }
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        try? await client.updateRowField(
            tableId: tableId, rowId: quote.id, fieldName: lastShownField, value: today
        )
    }
}
