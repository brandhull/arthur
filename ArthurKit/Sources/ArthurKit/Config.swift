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

/// App configuration. Synced across devices via iCloud Key-Value Storage
/// (NSUbiquitousKeyValueStore) as of Brandon's paid Apple Developer Program
/// membership — see the cloud sync section below load()/save(). Storage
/// backend is isolated behind this single load/save pair specifically so
/// that transition didn't need to touch any call site in the App or Bar
/// targets.
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
    /// Bumped on every save() — the only way to tell which of "the local
    /// file" and "iCloud's copy" is actually newer when they disagree,
    /// since Codable structs have no other ordering signal. Defaults to
    /// .distantPast (not .now) for configs decoded before this field
    /// existed, so an old local file always loses to a real cloud value
    /// instead of a stale local read winning just because it happened to
    /// decode a split-second before the cloud fetch resolved.
    public var lastModified: Date

    public init(craftLink: String = "", inboxes: [InboxDestination] = [],
                defaultInboxId: String? = nil, appearance: AppearanceMode = .platformDefault,
                baserowToken: String = "",
                baserowDatabases: [BaserowDatabase] = [],
                lastBaserowDatabaseId: Int? = nil, lastBaserowTableId: Int? = nil,
                senecaDatabaseId: Int? = nil, senecaTableId: Int? = nil,
                senecaQuoteField: String = "Quote", senecaAuthorField: String = "Author",
                rocksDocumentId: String? = nil, pinOnTop: Bool = false,
                lastModified: Date = .distantPast) {
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
        self.lastModified = lastModified
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
        lastModified = try c.decodeIfPresent(Date.self, forKey: .lastModified) ?? .distantPast
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

    // MARK: - iCloud sync
    //
    // NSUbiquitousKeyValueStore, not CloudKit or iCloud Documents — Config
    // is a small settings blob (well under NSUbiquitousKeyValueStore's 1MB
    // per-key/whole-store limits), which is exactly what key-value storage
    // is for; CloudKit/Documents are built for much larger or
    // relationally-structured data Arthur doesn't have here. All three
    // targets (Arthur-iOS, Arthur-Mac, ArthurBar) share one explicit
    // ubiquity-kvstore-identifier entitlement (see project.yml) rather than
    // each getting its own default per-bundle-ID store — without that,
    // "sync across my three devices" would silently only sync within a
    // single bundle ID, missing Mac entirely.
    //
    // Safe to call even before Brandon confirms the paid team/capability in
    // Xcode: NSUbiquitousKeyValueStore.default is always a valid object,
    // and reads/writes without the entitlement just silently no-op rather
    // than crashing — so this behaves as local-only until that's set up,
    // then starts syncing the moment it is, with no code change needed.
    private static let kvStore = NSUbiquitousKeyValueStore.default
    private static let kvKey = "config"

    /// Best-effort request to pull the latest values down from iCloud —
    /// call once at launch, before relying on load(). Apple's docs are
    /// explicit that this doesn't guarantee completion before returning;
    /// the actual arrival (if it's later than what load() already saw) is
    /// what NSUbiquitousKeyValueStore.didChangeExternallyNotification is
    /// for (see TaskStore's observer).
    public static func synchronizeCloud() {
        kvStore.synchronize()
    }

    private static func loadLocal() -> Config? {
        guard let data = try? Data(contentsOf: configFile),
              let cfg = try? JSONDecoder().decode(Config.self, from: data) else { return nil }
        return cfg
    }

    private static func loadFromCloud() -> Config? {
        guard let data = kvStore.data(forKey: kvKey),
              let cfg = try? JSONDecoder().decode(Config.self, from: data) else { return nil }
        return cfg
    }

    /// Merges whichever of local-file/iCloud is actually newer (by
    /// lastModified) rather than always preferring one — a device that's
    /// been offline and just reconnected shouldn't clobber a same-day edit
    /// made elsewhere, and a device that made the most recent real change
    /// shouldn't lose it to a stale cloud read on next launch. Adopting the
    /// winning side's value also mirrors it into the *other* store
    /// (local file or cloud, whichever lost) so both stay consistent
    /// going forward rather than only agreeing again after the next save().
    public static func load() -> Config {
        let local = loadLocal()
        let cloud = loadFromCloud()
        switch (local, cloud) {
        case (nil, nil):
            return Config()
        case (let l?, nil):
            return l
        case (nil, let c?):
            c.saveLocalOnly()
            return c
        case (let l?, let c?):
            if c.lastModified > l.lastModified {
                c.saveLocalOnly()
                return c
            } else if l.lastModified > c.lastModified {
                l.saveCloudOnly()
                return l
            }
            return l
        }
    }

    private func saveLocalOnly() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.configFile)
        }
    }

    private func saveCloudOnly() {
        if let data = try? JSONEncoder().encode(self) {
            Self.kvStore.set(data, forKey: Self.kvKey)
            Self.kvStore.synchronize()
        }
    }

    public func save() {
        var toSave = self
        toSave.lastModified = Date()
        toSave.saveLocalOnly()
        toSave.saveCloudOnly()
    }

    public var isConfigured: Bool { !craftLink.isEmpty && URL(string: craftLink) != nil }

    public var isBaserowConfigured: Bool { !baserowToken.isEmpty && !baserowDatabases.isEmpty }
}
