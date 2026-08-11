import SwiftUI

/// A bordered container for editable input — same hairline-stroke, flush-
/// with-the-page style as ContentBox, just semantically marking a field
/// (used by every input sheet: Add Task, Add Note, Quick Capture, Settings)
/// rather than a read-only display container (Tasks/Daily Note lists).
struct FieldBox<Content: View>: View {
    // Explicit, not @Environment(\.colorScheme) — see ContentBox's identical
    // comment.
    let scheme: ColorScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // No fill — flush with the page, same as ContentBox. FieldBox
            // used to carry a distinct lighter fill (Theme.fieldBackground)
            // on top of this same stroke, on the reasoning that an editable
            // field should read as its own "input" separate from a read-only
            // ContentBox. Brandon: that contrast just reads as "way off,"
            // the lighter panel has no reason to be there — the hairline
            // border alone is enough to bound the field, matching every
            // ContentBox in the app instead of standing out from them.
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.primary(scheme).opacity(Theme.borderOpacity), lineWidth: Theme.borderWidth)
            )
            .padding(.horizontal, 20)
    }
}

/// Shared field-section label style — "Task", "Capture", "Craft
/// connection", etc. — so every input sheet's labels match exactly instead
/// of each screen hand-rolling its own font/color/padding.
struct FieldLabel: View {
    let title: String
    var topPadding: CGFloat = 16

    var body: some View {
        Text(title)
            // Fixed size on Mac, not the .subheadline Dynamic Type token —
            // .subheadline resolves quite small on macOS specifically, and
            // Brandon flagged it (along with the Task filter labels) as too
            // small on a larger screen. iOS/iPadOS weren't flagged, so they
            // keep the scalable token.
            #if os(macOS)
            .font(.system(size: 15, weight: .semibold))
            #else
            .font(.system(.subheadline, weight: .semibold))
            #endif
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 20)
            .padding(.top, topPadding)
            .padding(.bottom, 8)
    }
}
