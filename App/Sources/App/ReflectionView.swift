import SwiftUI
import ArthurKit

/// Reflection tab — the daily note, renamed from "Daily Note" per Brandon's
/// request ("it's what I will use that feature for"). Shows the note
/// read-only by default with an Edit/Save/Cancel flow to rewrite it in
/// place, same shape as RocksView. The separate "append text" flow
/// (AddNoteSheet) still exists, but is no longer triggered from a button on
/// this tab — it's one of the floating "+" button's three options now,
/// alongside every other tab losing its own inline Add button.
struct ReflectionView: View {
    @ObservedObject var store: TaskStore
    @Environment(\.colorScheme) private var systemScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var isEditing = false
    @State private var draftContent = ""

    // See RocksView's identical comment — this previously never accounted
    // for Config.appearance at all.
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // Leading, not trailing — same position as the Tasks filter
                // and Quick Capture's Craft/Baserow toggle, so all four
                // tabs place their one header-row control in the identical
                // spot. PillActionButton also matches those two in size and
                // shape (a capsule, not PillButton's rounded rect).
                if isEditing {
                    PillActionButton(label: "Cancel", scheme: effectiveScheme) { isEditing = false }
                    PillActionButton(label: "Save", scheme: effectiveScheme) {
                        store.saveDailyNote(draftContent)
                        isEditing = false
                    }
                } else {
                    PillActionButton(label: "Edit", scheme: effectiveScheme) {
                        draftContent = store.dailyNoteContent
                        isEditing = true
                    }
                }
                Spacer()
                if store.dailyNoteSaving || store.dailyNoteLoading {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: Theme.headerRowHeight)
            .foregroundStyle(Theme.primary(effectiveScheme))

            // Top padding matches Quick Capture's own FieldBox/FieldLabel
            // spacing below its header row — see RocksView's identical
            // comment for the full reasoning.
            ContentBox(scheme: effectiveScheme) {
                if isEditing {
                    TextEditor(text: $draftContent)
                        .font(.system(size: inputFontSize))
                        .scrollContentBackground(.hidden)
                            .background(Color.clear) // macOS TextEditor keeps its own NSTextView background even with scrollContentBackground(.hidden) — this forces it transparent so FieldBox's own fill actually shows through, instead of a generic system gray that ignored Navy/Charcoal entirely.
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                        .padding(.trailing, 12)
                        .padding(.leading, 7)
                } else {
                    ScrollView {
                        if store.dailyNoteContent.isEmpty {
                            // Placeholder — system font, not Noto Serif (Brandon's
                            // request); the real note content below keeps the serif.
                            Text("Nothing here yet.")
                                .font(.system(size: inputFontSize))
                                .foregroundStyle(Theme.secondaryText(effectiveScheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        } else {
                            MarkdownContentView(markdown: store.dailyNoteContent, scheme: effectiveScheme)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                    }
                }
            }
            .padding(.top, 16)
        }
    }
}
