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
                // itself doesn't need to be tappable.
                Text(HomeTab.quickCapture.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText(effectiveScheme))
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
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
                        .font(.system(size: 13))
                    Spacer()
                }
                .foregroundStyle(Theme.secondaryText(effectiveScheme))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.background(effectiveScheme))
        .foregroundStyle(Theme.primary(effectiveScheme))
    }

    private func navRow(title: String, isActive: Bool, indent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                Spacer()
                if isActive {
                    Circle()
                        .fill(Theme.accentBright)
                        .frame(width: 6, height: 6)
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
