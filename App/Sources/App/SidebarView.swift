#if os(macOS)
import SwiftUI
import ArthurKit

/// Mac-only sidebar — Notion nav list (blue-dot active indicator) crossed
/// with Maverick's collapsible/resizable chrome. Dumb/stateless beyond its
/// own hover state: every real piece of state (selection, collapse,
/// quick-add/settings presentation) is owned by MacAgendaLayout and passed
/// in as bindings, so this view can't drift out of sync with the main pane.
struct SidebarView: View {
    @ObservedObject var store: TaskStore
    @Binding var selectedTab: HomeTab
    @Binding var quickCaptureSource: QuickCaptureSource
    @Binding var isCollapsed: Bool
    @Binding var showingSettings: Bool
    @Binding var showingAddTask: Bool
    @Binding var showingQuickAdd: Bool
    let effectiveScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { isCollapsed = true }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 15))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    showingQuickAdd = true
                } label: {
                    Image(systemName: "bubble.and.pencil")
                        .font(.system(size: 15))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // .bottom — grows downward from the button, away from the
                // window's top edge (this button sits right at the top of
                // the sidebar, so any edge that grows upward or is
                // vertically centered on it pushes part of the popover
                // above the window). NSPopover positions relative to the
                // screen, not the parent window, and does NOT clip itself
                // to the window's bounds — confirmed live that it was
                // genuinely rendering outside Arthur's own window, not just
                // a screenshot artifact. QuickAddModal's width is capped
                // (see its own comment) to also avoid overflowing left,
                // since .bottom still centers horizontally.
                .popover(isPresented: $showingQuickAdd, arrowEdge: .bottom) {
                    QuickAddModal(
                        store: store, selectedTab: $selectedTab,
                        showingAddTask: $showingAddTask, isPresented: $showingQuickAdd
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 2) {
                navRow(title: HomeTab.rocks.rawValue, isActive: selectedTab == .rocks) {
                    selectedTab = .rocks
                }
                navRow(title: HomeTab.tasks.rawValue, isActive: selectedTab == .tasks) {
                    selectedTab = .tasks
                }

                // Quick Capture: a non-interactive section label with two
                // indented, independently-selectable rows beneath it
                // (Craft/Baserow) — its content is always one or the other,
                // never an undifferentiated third state, so the parent label
                // itself doesn't need to be tappable. Same font/size/color as
                // every other nav row (Brandon: all sidebar text should read
                // as one uniform style, not a visually distinct section
                // header) — only the missing dot and disabled tap tell it
                // apart from an active/inactive leaf row. Same fixed 30pt
                // row height too, not its own top/bottom padding — that
                // used to make the gap above it (from Tasks) read as 12pt
                // while the gap below it (to Craft) read as only 4pt, so
                // Craft looked oddly "closer" to the label than every other
                // row is to its neighbor. Every row-to-row gap is now
                // exactly the same, set purely by this VStack's own
                // `spacing: 2`.
                Text(HomeTab.quickCapture.rawValue)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Theme.primary(effectiveScheme))
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                navRow(
                    title: QuickCaptureSource.craft.rawValue,
                    isActive: selectedTab == .quickCapture && quickCaptureSource == .craft,
                    indent: true
                ) {
                    selectedTab = .quickCapture
                    quickCaptureSource = .craft
                }
                navRow(
                    title: QuickCaptureSource.baserow.rawValue,
                    isActive: selectedTab == .quickCapture && quickCaptureSource == .baserow,
                    indent: true
                ) {
                    selectedTab = .quickCapture
                    quickCaptureSource = .baserow
                }

                navRow(title: HomeTab.reflection.rawValue, isActive: selectedTab == .reflection) {
                    selectedTab = .reflection
                }
            }
            .padding(.top, 4)

            Spacer()

            Button {
                showingSettings = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                    Text("Settings")
                        .font(.system(size: 14, weight: .regular))
                    Spacer()
                }
                .foregroundStyle(Theme.primary(effectiveScheme))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // No own background here — MacAgendaLayout paints this view onto a
        // rounded, distinctly-colored floating card from the outside
        // (Theme.sidebarCardBackground), inset with a margin on 3 sides.
        // Painting an opaque flat background here would sit on top of that
        // and erase the rounded corners.
        .foregroundStyle(Theme.primary(effectiveScheme))
    }

    private func navRow(title: String, isActive: Bool, indent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // 14pt system, default (primary) color, regular weight for
                // every row — selection is conveyed by the dot alone, not a
                // font-weight change, per Brandon's exact spec.
                Text(title)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Theme.primary(effectiveScheme))
                Spacer()
                if isActive {
                    Circle()
                        .fill(Theme.accentBright)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.leading, indent ? 26 : 14)
            .padding(.trailing, 14)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
