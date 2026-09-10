import SwiftUI
import ArthurKit

/// Tasks tab — extracted verbatim from AgendaView.taskSection so it's a
/// self-contained view (same pattern as RocksView/ReflectionView) that can be
/// dropped into either the iOS/iPadOS dropdown-tab layout or the Mac sidebar
/// layout unchanged. Pure refactor — no behavior change.
struct TasksView: View {
    @ObservedObject var store: TaskStore
    @Environment(\.colorScheme) private var systemScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

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

    /// Bumped up on Mac specifically — Brandon flagged the filter labels as
    /// too small on a larger screen, same complaint as FieldLabel. iOS/
    /// iPadOS weren't flagged, so they keep their original size.
    private var filterFontSize: CGFloat {
        #if os(macOS)
        return 14
        #else
        return 13
        #endif
    }

    // See RocksView's identical comment — Mac's sidebar redesign wants
    // display content flowing without a border, reserving borders for
    // actual forms (Baserow's Database/Table pickers).
    private var contentBordered: Bool {
        #if os(macOS)
        return false
        #else
        return true
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            // No "Tasks" heading here — the tab bar shows that now, and the
            // Add button that used to sit at the trailing end of this row
            // is gone too — the floating "+" button covers that now, so
            // this row is just the filter pills.
            HStack(spacing: 10) {
                PillFilterBar(
                    items: TaskFilter.allCases, label: \.rawValue,
                    selection: $store.filter, scheme: effectiveScheme, fontSize: filterFontSize
                )
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: Theme.headerRowHeight)
            .foregroundStyle(Theme.primary(effectiveScheme))

            // Top padding matches Quick Capture's own FieldBox/FieldLabel
            // spacing below its header row — see RocksView's comment for
            // the full reasoning; same fix applied identically here.
            ContentBox(scheme: effectiveScheme, bordered: contentBordered) {
                if store.filteredTasks.isEmpty {
                    // System font, not Noto Serif — Brandon's request; this is
                    // a placeholder state, not real content.
                    Text(store.isLoading ? "Loading…" : "Nothing here yet.")
                        .font(.system(size: inputFontSize))
                        .foregroundStyle(Theme.secondaryText(effectiveScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    List(store.filteredTasks) { task in
                        TaskRowView(task: task, store: store)
                            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                            .listRowBackground(Color.clear)
                            // Matches the same thin hairline every other
                            // border in the app now uses (sidebar/
                            // destination cards, FieldBox/ContentBox) —
                            // the system default separator read solidly
                            // gray/heavy next to those.
                            .listRowSeparatorTint(Theme.primary(effectiveScheme).opacity(Theme.borderOpacity))
                    }
                    .listStyle(.plain)
                    .cornerRadius(8)
                    .scrollContentBackground(.hidden)
                }
            }
            .padding(.top, 16)
        }
        // alignment: .top — otherwise frame(maxHeight: .infinity) centers this
        // VStack's now-short content (heading + one line of empty-state text)
        // within the tall imposed height, pushing content down with a gap
        // above it. Wasn't visible before because the empty state used to
        // have its own Spacers stretching the VStack to fill on its own.
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
