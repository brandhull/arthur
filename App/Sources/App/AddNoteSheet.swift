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

/// Built with FieldBox rather than native Form — matches the app-wide 8pt
/// corner radius (ContentBox/PillButton/Tasks List) instead of native Form's
/// grouped-section rounding. Still iOS/iPadOS's only way to reach "append to
/// daily note" (via the floating "+" menu) — Mac now also offers this
/// inline, via QuickAddModal's "New Reflection" option, using the same
/// DailyNoteComposeBox above rather than this sheet.
struct AddNoteSheet: View {
    @ObservedObject var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var text = ""

    private var effectiveScheme: ColorScheme {
        Theme.effectiveScheme(appearance: store.config.appearance, system: systemScheme)
    }

    private var inputFontSize: CGFloat {
        #if os(iOS)
        return Theme.inputFontSize(horizontalSizeClass: horizontalSizeClass)
        #else
        return Theme.inputFontSize()
        #endif
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                DailyNoteComposeBox(store: store, text: $text, effectiveScheme: effectiveScheme, inputFontSize: inputFontSize)
                    .padding(.top, 16)
            }
            .foregroundStyle(Theme.primary(effectiveScheme))
            .background(Theme.background(effectiveScheme))
            .navigationTitle("Add to Daily Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.appendToDailyNote(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(store.config.appearance == .system ? nil : effectiveScheme)
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 320, idealHeight: 360)
        #endif
    }
}
