#if os(iOS)
import SwiftUI
import ArthurKit

/// iPad-in-landscape's persistent sidebar — Brandon's explicit ask: "the
/// same visual layout as the Mac app, where the panel is collapsible and
/// so forth." Mirrors Mac's SidebarView + MacAgendaLayout sidebar-card
/// treatment exactly (floating rounded card, thin hairline border, a top
/// row with a collapse toggle + bubble.and.pencil quick-add popover, then
/// SidebarNavList below it) — just fixed-width and non-drag-resizable
/// (plain HStack at the call site, not Mac's AppKit-backed
/// ResizableHSplit, which doesn't compile on iOS anyway).
struct iPadLandscapeSidebar: View {
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
                .popover(isPresented: $showingQuickAdd) {
                    QuickAddModal(
                        store: store, selectedTab: $selectedTab,
                        showingAddTask: $showingAddTask, isPresented: $showingQuickAdd
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            SidebarNavList(
                selectedTab: $selectedTab, quickCaptureSource: $quickCaptureSource,
                showingSettings: $showingSettings, effectiveScheme: effectiveScheme
            )
        }
        .frame(width: Theme.sidebarIdealWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Theme.sidebarCardCornerRadius, style: .continuous)
                .fill(Theme.sidebarCardBackground(effectiveScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.sidebarCardCornerRadius, style: .continuous)
                .stroke(Theme.primary(effectiveScheme).opacity(Theme.borderOpacity), lineWidth: Theme.borderWidth)
        )
        .foregroundStyle(Theme.primary(effectiveScheme))
    }
}
#endif
