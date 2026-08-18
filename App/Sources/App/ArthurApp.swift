import SwiftUI

@main
struct ArthurApp: App {
    init() {
        // Only the splash screen still uses Noto Serif (Theme.serif) —
        // everywhere else is plain system font — but the font still has to
        // be registered at launch for that one screen to render it.
        FontLoader.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
