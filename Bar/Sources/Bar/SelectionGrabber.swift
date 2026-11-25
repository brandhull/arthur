import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Gets the text currently selected in whatever app is in front.
///
/// First choice is the Accessibility API (asks the app directly, never
/// touches the clipboard). Many apps (Chrome, Electron) don't answer it, so
/// the fallback presses ⌘C for you, reads the clipboard, and puts back
/// whatever was on it. Both paths need Accessibility permission.
@MainActor
enum SelectionGrabber {
    struct Result {
        var text: String?
        var needsPermission = false
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func grab() async -> Result {
        guard requestPermission() else { return Result(text: nil, needsPermission: true) }
        if let t = axSelectedText(), !t.isEmpty { return Result(text: t) }
        return Result(text: await copyViaKeystroke())
    }

    private static func axSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func copyViaKeystroke() async -> String? {
        // The hotkey's own modifiers (⌥⌘) are usually still down; give the
        // user a moment to let go so the app sees a plain ⌘C.
        let held: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let deadline = Date().addingTimeInterval(0.5)
        while !NSEvent.modifierFlags.intersection(held).isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        let before = pb.changeCount
        postCommandC()

        var copied: String?
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if pb.changeCount != before {
                copied = pb.string(forType: .string)
                break
            }
        }
        // Nothing selected leaves the clipboard untouched; otherwise put back
        // what the user had.
        if pb.changeCount != before { restore(saved, to: pb) }
        return copied
    }

    private static func postCommandC() {
        // Private source state so physically-held ⌥/⇧ don't leak into the
        // synthetic keystroke.
        let source = CGEventSource(stateID: .privateState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    private typealias Snapshot = [[(NSPasteboard.PasteboardType, Data)]]

    private static func snapshot(_ pb: NSPasteboard) -> Snapshot {
        (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    private static func restore(_ saved: Snapshot, to pb: NSPasteboard) {
        pb.clearContents()
        let items: [NSPasteboardItem] = saved.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }
}
