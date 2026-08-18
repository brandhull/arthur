import Foundation

public struct InboxDestination: Codable, Identifiable, Hashable {
    public var id: String        // resolved rootBlockId
    public var name: String      // display name, e.g. "Personal"
    public var url: String       // the original Craft doc URL, kept for re-resolving if needed

    public init(id: String, name: String, url: String) {
        self.id = id
        self.name = name
        self.url = url
    }
}

public enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    public var id: String { rawValue }

    /// Out-of-the-box default: dark on iOS/iPadOS, light on Mac — Brandon's
    /// explicit preference, not "follow the system" like every other setting
    /// here defaults to. Still fully overridable in Settings afterward; this
    /// only governs the very first launch (before any config.json exists).
    public static var platformDefault: AppearanceMode {
        #if os(macOS)
        return .light
        #else
        return .dark
        #endif
    }
}

/// App configuration. Local UserDefaults for now (v1) — iCloud key-value sync
/// is planned once Brandon's Apple Developer Program membership is renewed
/// (see SCOPE.md "Distribution"), so this is intentionally isolated behind a
/// single load/save pair to swap the storage backend later without touching
/// call sites.
public struct Config: Codable {
    public var craftLink: String
    public var inboxes: [InboxDestination]
    public var defaultInboxId: String?
    public var appearance: AppearanceMode
    public var baserowToken: String
    public var baserowDatabases: [BaserowDatabase]
    public var lastBaserowDatabaseId: Int?
    public var lastBaserowTableId: Int?
    public var senecaDatabaseId: Int?
    public var senecaTableId: Int?
    public var senecaQuoteField: String
    public var senecaAuthorField: String
    /// Cached rootBlockId for the "Rocks" doc in the "Personal" folder —
    /// resolved once via CraftClient.resolveDocument(title:folder:) rather
    /// than re-searching the folder on every launch. Cleared and re-resolved
    /// if a fetch using it ever fails (e.g. the doc was renamed/moved).
    public var rocksDocumentId: String?
    /// Mac-only ("pin window on top of all other windows"). Defaults off —
    /// Brandon's explicit ask for this to be an opt-in toggle, not a new
    /// always-on default.
    public var pinOnTop: Bool

    public init(craftLink: String = "", inboxes: [InboxDestination] = [],
                defaultInboxId: String? = nil, appearance: AppearanceMode = .platformDefault,
                baserowToken: String = "",
                baserowDatabases: [BaserowDatabase] = [],
                lastBaserowDatabaseId: Int? = nil, lastBaserowTableId: Int? = nil,
                senecaDatabaseId: Int? = nil, senecaTableId: Int? = nil,
                senecaQuoteField: String = "Quote", senecaAuthorField: String = "Author",
                rocksDocumentId: String? = nil, pinOnTop: Bool = false) {
        self.craftLink = craftLink
        self.inboxes = inboxes
        self.defaultInboxId = defaultInboxId
        self.appearance = appearance
        self.baserowToken = baserowToken
        self.baserowDatabases = baserowDatabases
        self.lastBaserowDatabaseId = lastBaserowDatabaseId
        self.lastBaserowTableId = lastBaserowTableId
        self.senecaDatabaseId = senecaDatabaseId
        self.senecaTableId = senecaTableId
        self.senecaQuoteField = senecaQuoteField
        self.senecaAuthorField = senecaAuthorField
        self.rocksDocumentId = rocksDocumentId
        self.pinOnTop = pinOnTop
    }

    /// Custom Decodable so an existing config.json saved before the Baserow
    /// fields existed still loads cleanly — the synthesized Decodable would
    /// otherwise fail on the missing keys and `load()` would fall back to a
    /// blank Config, silently wiping Brandon's craftLink/inboxes/etc.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        craftLink = try c.decodeIfPresent(String.self, forKey: .craftLink) ?? ""
        inboxes = try c.decodeIfPresent([InboxDestination].self, forKey: .inboxes) ?? []
        defaultInboxId = try c.decodeIfPresent(String.self, forKey: .defaultInboxId)
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .platformDefault
        baserowToken = try c.decodeIfPresent(String.self, forKey: .baserowToken) ?? ""
        baserowDatabases = try c.decodeIfPresent([BaserowDatabase].self, forKey: .baserowDatabases) ?? []
        lastBaserowDatabaseId = try c.decodeIfPresent(Int.self, forKey: .lastBaserowDatabaseId)
        lastBaserowTableId = try c.decodeIfPresent(Int.self, forKey: .lastBaserowTableId)
        senecaDatabaseId = try c.decodeIfPresent(Int.self, forKey: .senecaDatabaseId)
        senecaTableId = try c.decodeIfPresent(Int.self, forKey: .senecaTableId)
        senecaQuoteField = try c.decodeIfPresent(String.self, forKey: .senecaQuoteField) ?? "Quote"
        senecaAuthorField = try c.decodeIfPresent(String.self, forKey: .senecaAuthorField) ?? "Author"
        rocksDocumentId = try c.decodeIfPresent(String.self, forKey: .rocksDocumentId)
        pinOnTop = try c.decodeIfPresent(Bool.self, forKey: .pinOnTop) ?? false
    }

    /// nil means Craft's standard inbox — deliberately not a fallback to
    /// "whichever inbox doc was added first." A task destined for the
    /// standard inbox (e.g. Personal/Leapcure, per Brandon's actual workflow)
    /// must stay there even after Business/BYUI/Church docs are configured.
    public var defaultInbox: InboxDestination? {
        inboxes.first { $0.id == defaultInboxId }
    }

    /// A shared file under ~/Library/Application Support/Arthur, not
    /// UserDefaults — Arthur-Mac and ArthurBar are separate bundle IDs
    /// (different apps, same machine) and would not see each other's
    /// UserDefaults domain. A shared file lets both processes read/write the
    /// same config without needing an App Group entitlement (which requires
    /// the paid Apple Developer account — see SCOPE.md "Distribution").
    /// iOS/iPadOS get their own copy in the app's own container, since they
    /// can't share a file with a Mac app anyway; cross-device sync there is
    /// the planned iCloud work, still to come.
    public static var supportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Arthur", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var configFile: URL { supportDir.appendingPathComponent("config.json") }

    public static func load() -> Config {
        guard let data = try? Data(contentsOf: configFile),
              let cfg = try? JSONDecoder().decode(Config.self, from: data) else {
            return Config()
        }
        return cfg
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.configFile)
        }
    }

    public var isConfigured: Bool { !craftLink.isEmpty && URL(string: craftLink) != nil }

    public var isBaserowConfigured: Bool { !baserowToken.isEmpty && !baserowDatabases.isEmpty }
}
