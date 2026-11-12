import Foundation
import ArthurKit

/// Captures that were typed while clearly offline, sent in order once the
/// connection returns. A capture is queued only when the device positively
/// has no connection (path unsatisfied, or a "not connected" URLError) —
/// never on a timeout, which could mean the server already got it.
@MainActor
final class OutboxStore: ObservableObject {
    @Published private(set) var items: [OutboxItem] = OutboxStorage.load()
    private let network = NetworkMonitor()
    private var isDraining = false

    /// Called after items are delivered so the visible tabs can refresh.
    var onDelivered: ((Set<OutboxItem.Kind>) -> Void)?
    var configProvider: (() -> Config)?

    var isOnline: Bool { network.isOnline }
    var pendingCount: Int { items.filter { $0.failure == nil }.count }
    var attentionCount: Int { items.filter { $0.failure != nil }.count }

    init() {
        network.onReconnect = { [weak self] in
            Task { @MainActor in await self?.drain() }
        }
    }

    func enqueue(_ item: OutboxItem) {
        items.append(item)
        OutboxStorage.save(items)
    }

    func retry(_ item: OutboxItem) async {
        guard let index = items.firstIndex(of: item) else { return }
        items[index].failure = nil
        OutboxStorage.save(items)
        await drain()
    }

    func discard(_ item: OutboxItem) {
        items.removeAll { $0.id == item.id }
        OutboxStorage.save(items)
    }

    /// Sends waiting items oldest-first. Stops at the first "offline" error;
    /// any other error marks that one item as needing attention and moves on.
    func drain() async {
        guard !isDraining, network.isOnline, let config = configProvider?() else { return }
        isDraining = true
        defer { isDraining = false }
        var delivered = Set<OutboxItem.Kind>()
        for item in items where item.failure == nil {
            do {
                try await send(item, config: config)
                items.removeAll { $0.id == item.id }
                delivered.insert(item.kind)
            } catch {
                if isClearlyOffline(error) { break }
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].failure = error.localizedDescription
                }
            }
            OutboxStorage.save(items)
        }
        OutboxStorage.save(items)
        if !delivered.isEmpty { onDelivered?(delivered) }
    }

    private func record(createdPageId: String?, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].createdPageId = createdPageId
        OutboxStorage.save(items)
    }

    private func send(_ item: OutboxItem, config: Config) async throws {
        switch item.kind {
        case .bit:
            guard config.isBitsConfigured, let tableId = config.bitsTableId else { throw BaserowError.notConfigured }
            try await BitsClient(token: config.baserowToken, tableId: tableId).add(text: item.text)
        case .reflection:
            guard config.isConfigured else { throw CraftError.notConfigured }
            try await CraftClient(url: config.craftLink)
                .appendBlocksToDailyNote(day: item.day ?? "today", markdown: item.text)
        case .craftPage:
            guard config.isConfigured, let pageId = item.pageId else { throw CraftError.notConfigured }
            try await CraftClient(url: config.craftLink).appendBlocks(pageId: pageId, markdown: item.text)
        case .newPage:
            guard config.isConfigured, let title = item.title else { throw CraftError.notConfigured }
            let client = CraftClient(url: config.craftLink)
            // Create the page once; if a later step fails, the id is saved so
            // the retry appends to the same page instead of making another.
            var pageId = item.createdPageId
            if pageId == nil {
                pageId = try await client.createDocument(title: title, folderId: item.folderId)
                record(createdPageId: pageId, for: item.id)
            }
            if let pageId, !item.text.isEmpty {
                try await client.appendBlocks(pageId: pageId, markdown: item.text)
            }
        case .task:
            guard config.isConfigured else { throw CraftError.notConfigured }
            try await CraftClient(url: config.craftLink)
                .addTask(markdown: item.text, schedule: item.dueDay, deadline: nil, destinationBlockId: item.inboxId)
        case .baserow:
            guard !config.baserowToken.isEmpty else { throw BaserowError.notConfigured }
            guard let tableId = item.tableId, let json = item.fieldsJSON,
                  let fields = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
                throw BaserowError.badResponse
            }
            _ = try await BaserowClient(token: config.baserowToken).createRow(tableId: tableId, fields: fields)
        }
    }
}
