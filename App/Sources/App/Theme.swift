import SwiftUI
import ArthurKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum Theme {
    /// Brandon's preferred base color — used for "Arthur", buttons, and the
    /// Tasks/Daily Note section headings in light mode, and (via
    /// darkNavyBackground below) the "Navy" dark-mode background option.
    /// Matches Bits' navy exactly, for consistency across Brandon's apps.
    static let baseColor = Color(red: 0x10 / 255, green: 0x10 / 255, blue: 0x14 / 255) // #101014

    /// Light mode background: a very light grey, not pure white.
    static let lightBackground = Color(red: 0.953, green: 0.953, blue: 0.961) // ~#F3F3F5

    /// Dark mode background — Navy (Brandon compared it live against a
    /// Charcoal candidate via Settings; Navy won and Charcoal was removed).
    static let darkNavyBackground = baseColor

    /// Dark mode heading/button text — a light grey, not pure white, per
    /// Brandon's request.
    static let darkText = Color(red: 0.85, green: 0.85, blue: 0.87)

    static let accentBright = Color(red: 0.357, green: 0.608, blue: 1.0)   // #5B9BFF, still used for the checkbox fill
    static let accentDim    = Color(red: 0.18, green: 0.30, blue: 0.47)

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkNavyBackground : lightBackground
    }

    /// Resolves Config.appearance against the live system scheme — shared by
    /// every sheet (Settings, Add Task, Add Note, Quick Capture) so each can
    /// apply the same Theme.background(...)/preferredColorScheme(...) pairing
    /// AgendaView uses, instead of falling back to the generic system sheet
    /// background (which is what made Navy vs. Charcoal look identical in
    /// Settings — it was never reading darkStyle at all).
    static func effectiveScheme(appearance: AppearanceMode, system: ColorScheme) -> ColorScheme {
        switch appearance {
        case .system: return system
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Primary text/button color: baseColor in light mode, light grey in dark
    /// mode (never pure white/black at either end).
    static func primary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkText : baseColor
    }

    /// Concrete secondary/placeholder text color — NOT the same as
    /// `.foregroundStyle(.secondary)`. That's SwiftUI's *hierarchical*
    /// `.secondary` token, which tints relative to whatever ancestor
    /// `.foregroundStyle` is active rather than resolving to an absolute
    /// color. Quick Capture and Add Note's outer containers set
    /// `.foregroundStyle(Theme.primary(...))`, so a plain `.secondary`
    /// placeholder inside them came out visibly tinted navy-grey instead
    /// of the neutral system grey Tasks/Daily Note's placeholders show
    /// (their `.secondary` isn't nested under that override). Use this
    /// concrete color for any placeholder text so it matches everywhere
    /// regardless of ancestor styling — same fix pattern as
    /// `Color.primary` vs the hierarchical `.primary` token earlier.
    static func secondaryText(_ scheme: ColorScheme) -> Color {
        #if os(iOS)
        return Color(UIColor.secondaryLabel)
        #else
        return Color(NSColor.secondaryLabelColor)
        #endif
    }

    /// A dark neutral used only as the selected-pill fill/text pairing below
    /// — not a page background option (that's darkNavyBackground alone now).
    static let darkNeutral = Color(red: 0.11, green: 0.11, blue: 0.12)

    /// Selected-filter pill colors — explicitly not the system accent blue
    /// (Brandon: "I don't want that blue, even if it was from Bits"). Dark
    /// mode: light grey fill, dark neutral text. Light mode: dark neutral
    /// fill, light grey text — the inverse of the mode's own
    /// background/text pairing.
    static func selectedFilterBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkText : darkNeutral
    }
    static func selectedFilterForeground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? darkNeutral : darkText
    }

    /// Noto Serif, bundled in App/Resources/Fonts. Scoped to just the splash
    /// screen now — Brandon: everywhere else should be the plain system
    /// font, but the startup splash should keep this. Regular/Medium/
    /// SemiBold/Bold are separate static files with distinct PostScript
    /// names ("NotoSerif-Regular" / "NotoSerif-Medium" / "NotoSerif-SemiBold"
    /// / "NotoSerif-Bold") rather than one variable-weight family, so
    /// `.weight()` on a single Font.custom call won't select the right file
    /// — pick the PostScript name directly.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold: name = "NotoSerif-Bold"
        case .semibold: name = "NotoSerif-SemiBold"
        case .medium: name = "NotoSerif-Medium"
        case .light: name = "NotoSerif-Light"
        default: name = "NotoSerif-Regular"
        }
        return .custom(name, size: size)
    }

    /// Weight for "Arthur"/"Tasks"/"Daily Note" specifically. Mac-only: even
    /// Medium, then Regular, still read "cheap"/too bold to Brandon on that
    /// platform specifically (there are only two sections on the page — these
    /// don't need to stand out) — backed down to Light there. iOS/iPadOS keep
    /// Medium, unaffected.
    static var headingWeight: Font.Weight {
        #if os(macOS)
        return .light
        #else
        return .medium
        #endif
    }

    /// Size for "Tasks"/"Daily Note", and (since it's the same "default"
    /// size elsewhere in the app) the header date text too — see
    /// AgendaView.headerDateSize. With only two sections on the page, the
    /// section labels don't need to stand out as much as the app's own
    /// title. "Add Task"/"Add to Daily Note"/"Quick Capture" are unaffected
    /// — those are native/large sheet titles, a different case entirely.
    static var sectionHeadingSize: CGFloat {
        #if os(macOS)
        return 15
        #else
        return 20
        #endif
    }

    /// Fixed height for the row directly above each tab's main content box
    /// (Tasks' filter+Add row, Daily Note's Add row, Quick Capture's
    /// now-label-less spacer, Baserow's Database label). Tasks' row was
    /// naturally a hair taller than Daily Note's — its filter pill has more
    /// intrinsic height than a bare PillButton — which bumped its ContentBox
    /// top edge down slightly relative to Daily Note's. A shared fixed
    /// height (used instead of asymmetric top/bottom padding) forces all
    /// four tabs' content boxes to start at the exact same Y regardless of
    /// what's actually inside that row.
    ///
    /// Bumped from 44 — the row's own content (PillButton is ~34pt tall)
    /// left only ~5pt of margin above and below inside that height, which
    /// on a real device read as the filter pills/Add button sitting
    /// "anchored" flush against the ContentBox's top border rather than
    /// centered with real breathing room, even though they were already
    /// vertically centered within that cramped 44pt slot.
    static let headerRowHeight: CGFloat = 56

    /// Shared hairline weight for every border/outline/divider in the app —
    /// ContentBox, FieldBox, the Settings inline field replicas, the tab
    /// dropdown's outline, and the tab bar's underline. These had drifted
    /// into two different opacities (0.35 vs 0.15) despite comments in a
    /// couple of the 0.15 spots explicitly (and incorrectly) claiming they
    /// matched ContentBox — converged on 0.35, the majority/canonical value
    /// already used everywhere else. Width dropped 25% (1 -> 0.75) per
    /// Brandon's "very lean look" preference.
    static let borderOpacity: Double = 0.35
    static let borderWidth: CGFloat = 0.75

    /// Shared control height for the tab dropdown, the folder tabs (iPad),
    /// and the pill buttons (Today/Tomorrow, Craft/Baserow, Edit/Save/
    /// Cancel) — one source so pulling any of them up in isolation doesn't
    /// leave the others mismatched again. Brandon: after the tab bar became
    /// a dropdown, the pill buttons next to it read as noticeably shorter/
    /// "tiny" by comparison — this is what makes them match its height
    /// exactly instead of being sized off their own font's padding.
    static func controlHeight(horizontalSizeClass: UserInterfaceSizeClass? = nil) -> CGFloat {
        #if os(macOS)
        return 40
        #else
        return horizontalSizeClass == .regular ? 44 : 34
        #endif
    }

    /// Shared system-font size for every compose/input text area — Add
    /// Task's Task field, Add Note's compose box, and Quick Capture's
    /// Capture box. Brandon: these had drifted inconsistent (Quick Capture
    /// noticeably smaller, Add Note still serif from an earlier decision)
    /// and should read as the same field wherever you're typing, scaled up
    /// a bit on larger screens rather than staying one fixed size
    /// everywhere. Pass the environment's horizontalSizeClass on iOS/iPadOS
    /// (nil/omitted defaults to the phone-width size).
    static func inputFontSize(horizontalSizeClass: UserInterfaceSizeClass? = nil) -> CGFloat {
        #if os(macOS)
        return 14
        #else
        return horizontalSizeClass == .regular ? 18 : 16
        #endif
    }

}
