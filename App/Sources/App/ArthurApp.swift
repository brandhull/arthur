import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct ArthurApp: App {
    init() {
        FontLoader.registerBundledFonts()
        configureNavigationBarFont()
    }

    /// Sheets (Add Task, Add Note, Settings) use plain SwiftUI Form/List
    /// controls, which default to the system sans-serif font — that read as
    /// inconsistent with the Noto Serif used on the main screen. UIKit's
    /// large/inline nav-bar titles aren't reachable via a SwiftUI font()
    /// modifier, so this sets them globally via UINavigationBarAppearance
    /// once, after the bundled fonts are registered.
    private func configureNavigationBarFont() {
        #if os(iOS)
        guard let regular = UIFont(name: "NotoSerif-Regular", size: 17),
              let bold = UIFont(name: "NotoSerif-Bold", size: 34) else { return }
        let appearance = UINavigationBarAppearance()
        appearance.titleTextAttributes = [.font: regular]
        appearance.largeTitleTextAttributes = [.font: bold]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
