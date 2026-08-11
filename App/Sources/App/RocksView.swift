import SwiftUI
import ArthurKit

/// Rocks tab — reads and edits a single Craft page ("Rocks" in the
/// "Personal" folder) in place. Same read/edit/save shape as Reflection's
/// daily note, just backed by a resolved document id instead of a date.
/// Loading is triggered from AgendaView's top-level `.task`/scenePhase
/// handling, not here — same convention as Tasks/Daily Note, so all of a
/// tab's data loads together on launch/foreground rather than per-tab.
struct RocksView: View {
    @ObservedObject var store: TaskStore
    @Environment(\.colorScheme) private var systemScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var isEditing = false
    @State private var draftContent = ""

    // This view previously read @Environment(\.colorScheme) directly and
    // never accounted for Config.appearance at all — meaning if Brandon set
    // Arthur to Dark while his system was actually in Light (or vice
    // versa), Rocks would silently render in the wrong scheme regardless of
    // what he'd chosen in Settings. Same effectiveScheme pattern already
    // used by every sheet (AddTaskSheet, AddNoteSheet, SettingsView).
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
                        store.saveRocks(draftContent)
                        isEditing = false
                    }
                } else {
                    PillActionButton(label: "Edit", scheme: effectiveScheme) {
                        draftContent = store.rocksContent
                        isEditing = true
                    }
                }
                Spacer()
                if store.rocksSaving || store.rocksLoading {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: Theme.headerRowHeight)
            .foregroundStyle(Theme.primary(effectiveScheme))

            // Top padding matches Quick Capture's own FieldBox/FieldLabel
            // spacing below its header row — Quick Capture was the "correct"
            // one; Tasks/Rocks/Reflection's ContentBox previously sat flush
            // against the header row with no gap, which read as
            // inconsistent once compared side by side.
            ContentBox(scheme: effectiveScheme) {
                if isEditing {
                    TextEditor(text: $draftContent)
                        .font(.system(size: inputFontSize))
                        .scrollContentBackground(.hidden)
                            .background(Color.clear) // macOS TextEditor keeps its own NSTextView background even with scrollContentBackground(.hidden) — this forces it transparent so FieldBox's own fill actually shows through, instead of a generic system gray that ignored Navy/Charcoal entirely.
                        // Leading is 12 minus 5 to offset TextEditor's own
                        // built-in lineFragmentPadding — same fix as every
                        // other TextEditor in the app, keeps the cursor
                        // flush with where typed text visually starts.
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                        .padding(.trailing, 12)
                        .padding(.leading, 7)
                } else {
                    ScrollView {
                        if store.rocksContent.isEmpty {
                            Text(store.rocksLoading ? "Loading…" : "Nothing here yet.")
                                .font(.system(size: inputFontSize))
                                .foregroundStyle(Theme.secondaryText(effectiveScheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        } else {
                            MarkdownContentView(markdown: store.rocksContent, scheme: effectiveScheme)
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
