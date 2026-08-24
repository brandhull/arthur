import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct ArthurApp: App {
    // App-level, not local to QuickCaptureView — see QuickCaptureDraft's
    // own comment. Has to be owned above both scenes (the main WindowGroup
    // and, Mac-only, the Quick Capture pop-out Window) so both can share
    // the exact same instance via .environmentObject.
    @StateObject private var quickCaptureDraft = QuickCaptureDraft()

    init() {
        // Only the splash screen still uses Noto Serif (Theme.serif) —
        // everywhere else is plain system font — but the font still has to
        // be registered at launch for that one screen to render it.
        FontLoader.registerBundledFonts()

        #if os(iOS)
        // Works around a well-documented SwiftUI/UIKit bug, confirmed live
        // on iPhone (Brandon's screenshot): an *empty* TextEditor's caret
        // renders at UITextView's own default line-height instead of
        // whatever .font() size was requested, until the very first
        // keystroke — a too-tall, misaligned cursor next to a correctly-
        // sized placeholder. Not present on macOS (confirmed working there)
        // — NSTextView-backed TextEditor doesn't have this bug, only
        // UIKit's UITextView-backed one does.
        //
        // A custom UIViewRepresentable wrapper was tried first as a more
        // "proper" fix, but it turned out to not even accept focus/taps in
        // testing — a real bug of its own, not shipped. This is the
        // standard, much lower-risk alternative: UIAppearance proxies apply
        // to every UITextView at the moment it's created, including the
        // ones SwiftUI's native TextEditor creates internally — so setting
        // this once at launch changes what "brand new empty TextEditor"
        // uses as its initial caret font, before any of our own .font()
        // modifiers get a chance to apply. Every TextEditor in the app uses
        // 14-18pt depending on platform/size class (Theme.inputFontSize);
        // 16 is the common iPhone-compact value and closest single
        // approximation across all of them — this only affects the
        // cosmetic caret height in the empty-field instant before typing,
        // not any actual text rendering, so it doesn't need to be exact.
        UITextView.appearance().font = .systemFont(ofSize: 16)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(quickCaptureDraft)
        }

        #if os(macOS)
        // Window (singular), not WindowGroup — inherently single-instance:
        // calling openWindow(id:) again while one's already open just
        // brings the existing one forward instead of spawning a second,
        // which is exactly Brandon's "only one pop-out at a time" ask, with
        // no manual bookkeeping needed.
        Window("Quick Capture", id: "quickCapturePopout") {
            QuickCapturePopoutView()
                .environmentObject(quickCaptureDraft)
        }
        #endif
    }
}
