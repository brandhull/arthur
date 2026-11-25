import SwiftUI
import ArthurKit

/// Arthur's own colors for ArthurBar's windows and toasts, following the same
/// light / dark / system choice as the main app (Config.appearance). The
/// values mirror Theme.swift in the main app target, which Bar doesn't
/// compile.
enum BarTheme {
    static let base = Color(red: 0x10 / 255, green: 0x10 / 255, blue: 0x14 / 255)           // #101014
    static let lightBackground = Color(red: 0.953, green: 0.953, blue: 0.961)               // ~#F3F3F5
    static let darkText = Color(red: 211.0 / 255, green: 211.0 / 255, blue: 211.0 / 255)    // #D3D3D3
    static let darkNeutral = Color(red: 0.11, green: 0.11, blue: 0.12)

    @MainActor
    static var scheme: ColorScheme {
        switch Config.load().appearance {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? .dark : .light
        }
    }

    static func background(_ s: ColorScheme) -> Color { s == .dark ? base : lightBackground }
    static func card(_ s: ColorScheme) -> Color { s == .dark ? darkNeutral : .white }
    static func text(_ s: ColorScheme) -> Color { s == .dark ? darkText : base }
    static let cornerRadius: CGFloat = 10
}
