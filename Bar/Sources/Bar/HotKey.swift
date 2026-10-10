import AppKit
import Carbon.HIToolbox

/// A user-configurable global shortcut: Carbon key code + modifiers, plus the
/// pieces needed to show it (display) and mirror it on a menu item (keyChar).
struct HotKeySpec: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon modifier mask
    var display: String     // e.g. "⌥⌘Space"
    var keyChar: String     // menu keyEquivalent, e.g. " "

    static let `default` = HotKeySpec(keyCode: 49,
                                      modifiers: UInt32(cmdKey | optionKey),
                                      display: "⌥⌘Space",
                                      keyChar: " ")

    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    static func from(event: NSEvent) -> HotKeySpec {
        let mods = carbonModifiers(from: event.modifierFlags)
        var symbols = ""
        if event.modifierFlags.contains(.control) { symbols += "⌃" }
        if event.modifierFlags.contains(.option) { symbols += "⌥" }
        if event.modifierFlags.contains(.shift) { symbols += "⇧" }
        if event.modifierFlags.contains(.command) { symbols += "⌘" }
        let names: [UInt16: String] = [
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        let keyName = names[event.keyCode]
            ?? (event.charactersIgnoringModifiers ?? "?").uppercased()
        return HotKeySpec(keyCode: UInt32(event.keyCode),
                          modifiers: mods,
                          display: symbols + keyName,
                          keyChar: event.charactersIgnoringModifiers ?? "")
    }
}

/// Global hotkey via Carbon RegisterEventHotKey — works from an accessory app
/// with no accessibility permissions required.
///
/// Each instance installs its own event handler, but all of them share the
/// same `GetApplicationEventTarget()` — Carbon doesn't automatically scope a
/// kEventHotKeyPressed event to only the handler that registered that
/// specific key combo, it dispatches to the handler chain on that target.
/// The handler itself has to read the event's own EventHotKeyID (via
/// GetEventParameter) and compare it against the id *this* instance
/// registered before deciding the press was actually its own. Previously
/// every instance used the same hardcoded `id: 1` and the callback never
/// checked it at all — it just ran unconditionally whenever any handler on
/// that target fired, which is why Quick Task and Quick Capture's hotkeys
/// ended up both triggering whichever one Carbon happened to dispatch to
/// (Brandon: "no matter what this says, both hotkeys bring up Quick
/// Capture"). Each instance now gets a unique id (a simple atomic counter)
/// and the callback ignores any event whose id doesn't match its own.
final class HotKey {
    private static var nextID: UInt32 = 1
    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let callback: () -> Void

    /// ⌥⌘Space by default (keyCode 49 = space).
    init?(keyCode: UInt32 = 49,
          modifiers: UInt32 = UInt32(cmdKey | optionKey),
          callback: @escaping () -> Void) {
        self.callback = callback
        self.id = Self.nextID
        Self.nextID += 1

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            // Returning noErr tells Carbon "handled, stop walking the
            // handler chain" — every installed HotKey's handler sits on
            // this same shared target, so a non-match has to return
            // eventNotHandledErr instead, or it silently swallows the
            // event before the handler that actually owns this id ever
            // gets a turn (confirmed live: whichever HotKey was installed
            // most recently always won, for every combo, until this was
            // fixed — the ID check alone wasn't enough without this).
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var firedID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &firedID)
            guard status == noErr else { return OSStatus(eventNotHandledErr) }
            let hk = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            guard firedID.id == hk.id else { return OSStatus(eventNotHandledErr) }
            DispatchQueue.main.async { hk.callback() }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x43514341), id: id) // "CQCA"
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { return nil }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
