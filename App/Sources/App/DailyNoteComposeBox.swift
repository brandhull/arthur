import SwiftUI

/// The shared text-entry+placeholder body for "append to today's daily
/// note" — extracted out of AddNoteSheet so QuickAddModal's inline "New
/// Reflection" compose box (Mac sidebar redesign) can reuse the exact same
/// placeholder/PlainTextEditor logic instead of a second hand-copied version.
struct DailyNoteComposeBox: View {
    @ObservedObject var store: TaskStore
    @Binding var text: String
    let effectiveScheme: ColorScheme
    let inputFontSize: CGFloat
    // AddNoteSheet's full-page sheet context still wants the bordered field
    // look; QuickAddModal's inline "New Reflection" compose box (a small
    // popover, not a page) doesn't — Brandon: no container there, just text
    // flowing freely under the "New Reflection" header.
    var bordered: Bool = true

    var body: some View {
        // Switched from serif to system font — Brandon wanted this compose
        // box, Add Task's Task field, and Quick Capture's Capture box to all
        // read as the same field (they'd drifted inconsistent), overriding
        // the earlier "matches how you'll read it back" reasoning for
        // keeping this one serif. The saved note's read-only display in
        // ReflectionView still uses serif — this is just the compose/input
        // experience.
        Group {
            if bordered {
                FieldBox(scheme: effectiveScheme) { composeArea }
            } else {
                // FieldBox always adds its own 20pt horizontal padding,
                // baked in regardless of `bordered` — fine for a full-page
                // sheet, but inside QuickAddModal's small popover it would
                // sit inconsistently inset from the "New Reflection" header
                // above it (14pt). Bypassing FieldBox entirely when
                // unbordered lets the text area align flush with that
                // header instead.
                composeArea
            }
        }
    }

    private var composeArea: some View {
        ZStack(alignment: .topLeading) {
            // Same placeholder treatment as Quick Capture's Capture
            // field, for consistency — TextEditor has no native
            // placeholder support.
            if text.isEmpty {
                Text("Nothing here yet.")
                    .font(.system(size: inputFontSize))
                    .foregroundStyle(Theme.secondaryText(effectiveScheme))
                    .padding(12)
                    .allowsHitTesting(false)
            }
            PlainTextEditor(text: $text, fontSize: inputFontSize, scheme: effectiveScheme)
                .frame(minHeight: 160)
        }
        // FieldBox used to be what gave this width to fill its container —
        // bypassing FieldBox for the unbordered path (see `bordered` above)
        // dropped that constraint too, which is what broke the popover's
        // layout (text area collapsing to its intrinsic size instead of
        // filling the available width). Restated explicitly here so both
        // the bordered and unbordered paths size identically.
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

