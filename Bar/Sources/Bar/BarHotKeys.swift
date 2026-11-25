import Foundation
import Carbon.HIToolbox

/// Persisted, user-configurable hotkeys for ArthurBar's two panels —
/// reintroduced after being hardcoded (⌥⌘A / ⌥⌘C, no way to change them).
/// Deliberately plain UserDefaults, not part of ArthurKit's shared Config
/// (which syncs across devices via iCloud KVS): a Mac-only hotkey has no
/// meaning on iPhone/iPad, so it stays local — same reasoning as
/// MacAgendaLayout's "sidebarCollapsed" AppStorage.
struct BarHotKeys: Codable {
    var addTask: HotKeySpec
    var quickCapture: HotKeySpec
    var clip: HotKeySpec

    private enum CodingKeys: String, CodingKey { case addTask, quickCapture, clip }

    init(addTask: HotKeySpec, quickCapture: HotKeySpec, clip: HotKeySpec) {
        self.addTask = addTask
        self.quickCapture = quickCapture
        self.clip = clip
    }

    // `clip` was added later; older saved hotkeys must keep their rebinds.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        addTask = try c.decode(HotKeySpec.self, forKey: .addTask)
        quickCapture = try c.decode(HotKeySpec.self, forKey: .quickCapture)
        clip = try c.decodeIfPresent(HotKeySpec.self, forKey: .clip) ?? Self.defaultClip
    }

    static let defaultAddTask = HotKeySpec(
        keyCode: 0, modifiers: UInt32(cmdKey | optionKey), display: "⌥⌘A", keyChar: "a"
    )
    static let defaultQuickCapture = HotKeySpec(
        keyCode: 8, modifiers: UInt32(cmdKey | optionKey), display: "⌥⌘C", keyChar: "c"
    )
    static let defaultClip = HotKeySpec(
        keyCode: 1, modifiers: UInt32(cmdKey | optionKey), display: "⌥⌘S", keyChar: "s"
    )
    static let `default` = BarHotKeys(addTask: defaultAddTask, quickCapture: defaultQuickCapture, clip: defaultClip)

    private static let defaultsKey = "arthurbar.hotkeys"

    static func load() -> BarHotKeys {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(BarHotKeys.self, from: data)
        else { return .default }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
