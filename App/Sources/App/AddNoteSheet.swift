import SwiftUI

/// Built with FieldBox rather than native Form — matches the app-wide 8pt
/// corner radius (ContentBox/PillButton/Tasks List) instead of native Form's
/// grouped-section rounding.
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
                FieldBox(scheme: effectiveScheme) {
                    // Switched from serif to system font — Brandon wanted
                    // this compose box, Add Task's Task field, and Quick
                    // Capture's Capture box to all read as the same field
                    // (they'd drifted inconsistent), overriding the earlier
                    // "matches how you'll read it back" reasoning for
                    // keeping this one serif. The saved note's read-only
                    // display in DailyNoteView still uses serif — this is
                    // just the compose/input experience.
                    ZStack(alignment: .topLeading) {
                        // Same placeholder treatment as Quick Capture's
                        // Capture field, for consistency — TextEditor has
                        // no native placeholder support.
                        if text.isEmpty {
                            Text("Nothing here yet.")
                                .font(.system(size: inputFontSize))
                                .foregroundStyle(Theme.secondaryText(effectiveScheme))
                                // Same uniform .padding(12) as the Tasks/Daily
                                // Note placeholders — this must match exactly
                                // across all four empty states, so the cursor
                                // alignment fix below happens on the
                                // TextEditor's side instead of here.
                                .padding(12)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $text)
                            .font(.system(size: inputFontSize))
                            .scrollContentBackground(.hidden)
                            .background(Color.clear) // macOS TextEditor keeps its own NSTextView background even with scrollContentBackground(.hidden) — this forces it transparent so FieldBox's own fill actually shows through, instead of a generic system gray that ignored Navy/Charcoal entirely.
                            // Leading is 12 minus 5: TextEditor bakes in a
                            // fixed 5pt lineFragmentPadding on both platforms
                            // that a plain Text has no equivalent of, so
                            // giving it the same 12 as the placeholder would
                            // put the actual cursor/typed-text position 5pt
                            // to the right of the placeholder's "N". This
                            // keeps the cursor flush with the placeholder
                            // without touching the placeholder's own padding.
                            .padding(.top, 12)
                            .padding(.bottom, 12)
                            .padding(.trailing, 12)
                            .padding(.leading, 7)
                            .frame(minHeight: 160)
                    }
                }
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
