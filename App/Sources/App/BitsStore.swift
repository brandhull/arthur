import Foundation
import ArthurKit

/// State behind the Bits tab: the list (Bits or Archive), plus the
/// add/edit/archive/delete operations against Baserow. Every mutation is
/// optimistic where it removes a card (archive/delete) and puts the card
/// back if Baserow rejects it.
@MainActor
final class BitsStore: ObservableObject {
    @Published private(set) var bits: [Bit] = []
    @Published var showingArchive = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    /// Set by `add` when it failed because the device is clearly offline,
    /// so the caller can queue the Bit instead of reporting an error.
    private(set) var lastAddWasOffline = false

    /// Guards against an older, slower fetch landing after a newer one (e.g.
    /// toggling Bits/Archive quickly) and overwriting the list with the
    /// wrong side.
    private var loadGeneration = 0

    private func client(_ config: Config) -> BitsClient? {
        guard config.isBitsConfigured, let tableId = config.bitsTableId else { return nil }
        return BitsClient(token: config.baserowToken, tableId: tableId)
    }

    func load(_ config: Config) async {
        guard let client = client(config) else {
            bits = []
            return
        }
        loadGeneration += 1
        let generation = loadGeneration
        let archived = showingArchive
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let result = try await client.list(archived: archived)
            guard generation == loadGeneration else { return }
            bits = result
            errorMessage = nil
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    func setShowingArchive(_ archive: Bool, config: Config) async {
        guard archive != showingArchive else { return }
        showingArchive = archive
        bits = []
        await load(config)
    }

    /// Creates a new Bit and refreshes the (non-archive) list so it shows at
    /// the top. Returns whether Baserow accepted it, so the capture screen
    /// can keep the text on failure.
    func add(text: String, config: Config) async -> Bool {
        lastAddWasOffline = false
        guard let client = client(config) else {
            errorMessage = "Choose your Bits table in Settings."
            return false
        }
        do {
            try await client.add(text: text)
        } catch {
            lastAddWasOffline = isClearlyOffline(error)
            errorMessage = error.localizedDescription
            return false
        }
        showingArchive = false
        await load(config)
        return true
    }

    func saveEdit(_ bit: Bit, text: String, config: Config) async -> Bool {
        guard let client = client(config) else { return false }
        do {
            try await client.update(id: bit.id, text: text)
            if let index = bits.firstIndex(where: { $0.id == bit.id }) { bits[index].text = text }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Archives (or, from the Archive view, restores) a Bit.
    func setArchived(_ bit: Bit, archived: Bool, config: Config) async {
        await removeOptimistically(bit, config: config) { try await $0.setArchived(id: bit.id, archived: archived) }
    }

    func delete(_ bit: Bit, config: Config) async {
        await removeOptimistically(bit, config: config) { try await $0.delete(id: bit.id) }
    }

    /// Drops the card immediately, runs the Baserow call, and puts the card
    /// back in its newest-first spot if the call fails.
    private func removeOptimistically(_ bit: Bit, config: Config,
                                      _ operation: (BitsClient) async throws -> Void) async {
        guard let client = client(config) else { return }
        bits.removeAll { $0.id == bit.id }
        do {
            try await operation(client)
            errorMessage = nil
        } catch {
            bits.append(bit)
            bits.sort { $0.id > $1.id }
            errorMessage = error.localizedDescription
        }
    }
}
