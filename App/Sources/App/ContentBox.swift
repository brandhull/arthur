import SwiftUI

/// A bordered container for a section's content (task list / daily note text)
/// so it reads as its own bounded region rather than bleeding to the window's
/// full width — per Brandon's Mac mockup.
struct ContentBox<Content: View>: View {
    // Explicit, not @Environment(\.colorScheme) — that's meant to track the
    // real system appearance, which drifts from Arthur's own forced
    // Config.appearance state in exactly the kind of case Brandon flagged
    // (a form/page rendering with the wrong-for-the-mode color).
    // Every call site already has its own computed `effectiveScheme` handy,
    // so this just takes it directly instead of re-deriving it a second,
    // less reliable way.
    let scheme: ColorScheme
    // Search Baserow's results container wants ContentBox's exact shape and
    // margins but explicitly no visible border ("invisible, not gray" —
    // Brandon's words) — everywhere else keeps the hairline stroke, so this
    // defaults to on rather than threading a new param through every
    // existing call site.
    var bordered: Bool = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // .overlay, not .background — a background stroke draws behind
            // the content, and a ScrollView's own clipping/edge rendering
            // (Daily Note) painted over the top edge specifically, making it
            // look "MIA" while the Tasks List's edges happened to survive.
            // Overlay always draws on top, so all four sides show reliably
            // regardless of what the child content does internally.
            .overlay(
                // Bumped from 0.15 opacity/0.5pt — the same too-faint
                // combination that made the selected tab's outline nearly
                // invisible on retina displays turned out to affect this
                // stroke too, making ContentBox (Tasks/Daily Note) read as
                // borderless next to FieldBox's clearly-visible filled
                // boxes (Quick Capture, Add Task, Settings) right beside it.
                bordered ?
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.primary(scheme).opacity(Theme.borderOpacity), lineWidth: Theme.borderWidth)
                : nil
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
    }
}
