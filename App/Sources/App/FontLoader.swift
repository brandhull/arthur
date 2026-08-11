import CoreText
import Foundation

/// Registers the bundled Noto Serif files with CoreText at launch. Works
/// identically on iOS/iPadOS/macOS, so it avoids the iOS-only `UIAppFonts`
/// Info.plist key and the separate macOS `ATSApplicationFontsPath` mechanism.
enum FontLoader {
    static func registerBundledFonts() {
        let names = ["NotoSerif-Light", "NotoSerif-Regular", "NotoSerif-Medium", "NotoSerif-SemiBold", "NotoSerif-Bold"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }
}
