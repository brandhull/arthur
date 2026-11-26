import Foundation

/// The page every clip is appended to, plus a short history of recent clips.
/// Mac-local (UserDefaults), like the hotkeys: a clip target means nothing on
/// iPhone, so it doesn't ride along in the synced Config.
struct ClipPage: Codable, Equatable {
    var id: String
    var title: String
}

struct ClipRecord: Codable, Identifiable {
    var id = UUID()
    var text: String
    var pageTitle: String
    var date = Date()
    /// Optional so history saved before image clips still decodes.
    var isImage: Bool?
}

enum ClipStore {
    private static let pageKey = "arthurbar.clipPage"
    private static let recentsKey = "arthurbar.recentClips"
    private static let maxRecents = 8

    static var page: ClipPage? {
        get {
            guard let data = UserDefaults.standard.data(forKey: pageKey) else { return nil }
            return try? JSONDecoder().decode(ClipPage.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: pageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: pageKey)
            }
        }
    }

    static var recents: [ClipRecord] {
        guard let data = UserDefaults.standard.data(forKey: recentsKey),
              let list = try? JSONDecoder().decode([ClipRecord].self, from: data) else { return [] }
        return list
    }

    static func record(text: String, pageTitle: String) {
        insert(ClipRecord(text: text, pageTitle: pageTitle))
    }

    static func recordImage(pageTitle: String) {
        insert(ClipRecord(text: "", pageTitle: pageTitle, isImage: true))
    }

    private static func insert(_ record: ClipRecord) {
        var list = recents
        list.insert(record, at: 0)
        if list.count > maxRecents { list = Array(list.prefix(maxRecents)) }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }
}
