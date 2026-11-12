import Foundation
import Network

/// One capture that couldn't be sent because the device was clearly offline,
/// waiting on disk until it can be.
public struct OutboxItem: Codable, Identifiable, Equatable {
    public enum Kind: String, Codable {
        case bit        // new row in the Bits table
        case reflection // append to a day's Craft daily note
        case craftPage  // append to a specific Craft page
        case newPage    // create a Craft page in a folder (title + body)
        case task       // add a Craft task
        case baserow    // new row in a Baserow table
    }

    public let id: UUID
    public let kind: Kind
    /// For `.craftPage` this is the final markdown (separator included).
    public let text: String
    /// `.craftPage`: destination page id and display title.
    public let pageId: String?
    public let pageTitle: String?
    /// `.reflection`: the day it was written for (`yyyy-MM-dd`), so a note
    /// typed Monday night lands on Monday even if it sends on Tuesday.
    public let day: String?
    /// `.newPage`: the title, destination folder, and — once the page has
    /// been created but its body not yet appended — the new page's id, so a
    /// resumed send never creates the page twice.
    public let title: String?
    public let folderId: String?
    public var createdPageId: String?
    /// `.task`: due day (`yyyy-MM-dd`) and the inbox document id, if any.
    public let dueDay: String?
    public let inboxId: String?
    /// `.baserow`: target table and the JSON-encoded field payload.
    public let tableId: Int?
    public let fieldsJSON: Data?
    public let createdAt: Date
    /// Set when a send failed for a reason other than being offline. Items
    /// with a failure are never retried automatically; the user decides.
    public var failure: String?

    public init(kind: Kind, text: String, pageId: String? = nil, pageTitle: String? = nil, day: String? = nil,
                title: String? = nil, folderId: String? = nil, createdPageId: String? = nil,
                dueDay: String? = nil, inboxId: String? = nil,
                tableId: Int? = nil, fieldsJSON: Data? = nil) {
        self.id = UUID()
        self.kind = kind
        self.text = text
        self.pageId = pageId
        self.pageTitle = pageTitle
        self.day = day
        self.title = title
        self.folderId = folderId
        self.createdPageId = createdPageId
        self.dueDay = dueDay
        self.inboxId = inboxId
        self.tableId = tableId
        self.fieldsJSON = fieldsJSON
        self.createdAt = Date()
        self.failure = nil
    }

    public var label: String {
        switch kind {
        case .bit: return "Bit"
        case .reflection: return "Reflection"
        case .craftPage: return pageTitle ?? "Craft page"
        case .newPage: return "New page" + (title.map { ": " + $0 } ?? "")
        case .task: return "Task"
        case .baserow: return "Baserow row"
        }
    }

    public static func todayString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

/// On-disk persistence for the outbox (atomic writes, like the other caches).
public enum OutboxStorage {
    private static var fileURL: URL { Config.supportDir.appendingPathComponent("outbox.json") }

    public static func load() -> [OutboxItem] {
        (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([OutboxItem].self, from: $0) } ?? []
    }

    public static func save(_ items: [OutboxItem]) {
        if items.isEmpty {
            try? FileManager.default.removeItem(at: fileURL)
        } else if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

/// True only when the error says the device itself has no usable connection.
/// Timeouts and server errors are deliberately NOT included: the request may
/// have reached the server, and queueing then could create duplicates.
public func isClearlyOffline(_ error: Error) -> Bool {
    guard let urlError = error as? URLError else { return false }
    switch urlError.code {
    case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .cannotFindHost, .dnsLookupFailed:
        return true
    default:
        return false
    }
}

/// Watches the system's network path. `isOnline` stays true until the OS
/// positively reports no connection, so a slow first callback never queues
/// something unnecessarily.
public final class NetworkMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "arthur.network")
    private let lock = NSLock()
    private var online = true
    public var onReconnect: (@Sendable () -> Void)?

    public var isOnline: Bool { lock.lock(); defer { lock.unlock() }; return online }

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let nowOnline = path.status == .satisfied
            self.lock.lock()
            let wasOnline = self.online
            self.online = nowOnline
            self.lock.unlock()
            if nowOnline && !wasOnline { self.onReconnect?() }
        }
        monitor.start(queue: queue)
    }
}
