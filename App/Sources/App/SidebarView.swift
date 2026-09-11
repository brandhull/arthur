#if os(macOS)
import SwiftUI
import ArthurKit

/// Mac-only sidebar — Notion nav list (blue-dot active indicator) crossed
/// with Maverick's collapsible/resizable chrome. Dumb/stateless beyond its
/// own hover state: every real piece of state (selection, collapse,
/// quick-add/settings presentation) is owned by MacAgendaLayout and passed
/// in as bindings, so this view can't drift out of sync with the main pane.
/// The actual nav rows live in SidebarNavList (shared with the iOS drawer
/// and the iPad landscape sidebar) — this view owns just the top row
/// (collapse toggle + quick-add) that's specific to Mac's chrome.
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

                // Presentation lives at AgendaView's top level now
                // (CenteredModal, mounted once, shared by every platform) —
                // this button just flips the shared showingQuickAdd flag
                // instead of anchoring its own popover, which used to
                // render outside the window entirely at certain sidebar
                // widths (NSPopover positions relative to the screen, not
                // the parent window, and doesn't clip to its bounds).
                Button {
                    showingQuickAdd = true
                } label: {
                    Image(systemName: "bubble.and.pencil")
                        .font(.system(size: 15))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            SidebarNavList(
                selectedTab: $selectedTab, quickCaptureSource: $quickCaptureSource,
                showingSettings: $showingSettings, effectiveScheme: effectiveScheme
            )
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // No own background here — MacAgendaLayout paints this view onto a
        // rounded, distinctly-colored floating card from the outside
        // (Theme.sidebarCardBackground), inset with a margin on 3 sides.
        // Painting an opaque flat background here would sit on top of that
        // and erase the rounded corners.
        .foregroundStyle(Theme.primary(effectiveScheme))
    }
}
#endif
