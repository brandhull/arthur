import SwiftUI

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
