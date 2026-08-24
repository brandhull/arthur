#if os(macOS)
import SwiftUI
import AppKit

/// Restores/persists a window's size+position across full launches, keyed
/// by `name` — NSWindow.setFrameAutosaveName is a built-in AppKit mechanism
/// made for exactly this (backed by UserDefaults under the hood); AppKit
/// handles saving on every move/resize and restoring on the next window
/// with the same name, no manual notification wiring needed. Set once, not
/// re-applied on every SwiftUI update — calling it repeatedly is harmless
/// but pointless.
private struct FrameAutosaveAccessor: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.setFrameAutosaveName(name)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func restoresFrame(named name: String) -> some View {
        background(FrameAutosaveAccessor(name: name))
    }
}
#endif
