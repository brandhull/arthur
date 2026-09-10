#if os(macOS)
import SwiftUI
import ArthurKit

/// Mac-only root layout — Notion/Maverick-style collapsible, resizable
/// sidebar (HSplitView, not NavigationSplitView: the sidebar needs custom
/// chrome — a quick-add button, a gear pinned to the bottom, nested Quick
/// Capture rows — that NavigationSplitView's system-owned collapse/toolbar
/// model doesn't cleanly accommodate) plus one main content pane. Replaces
/// AgendaView's old dropdown+floating-"+"-button chrome on Mac only; iOS/
/// iPadOS keep that layout entirely, unchanged, via AgendaView's own
/// `#if os(macOS)` branch.
struct MacAgendaLayout<Content: View>: View {
    @ObservedObject var store: TaskStore
    @Binding var selectedTab: HomeTab
    @Binding var quickCaptureSource: QuickCaptureSource
    @Binding var showingSettings: Bool
    @Binding var showingAddTask: Bool
    let effectiveScheme: ColorScheme
    let content: Content

    // Pure Mac window-chrome prefs — deliberately @AppStorage, not part of
    // the cross-device Config/iCloud-KVS system: nothing here needs to sync
    // across devices, and mixing single-window layout state into Config
    // would just add sync-conflict surface for no benefit.
    @AppStorage("sidebarCollapsed") private var sidebarCollapsed = false
    @State private var showingQuickAdd = false

    init(
        store: TaskStore, selectedTab: Binding<HomeTab>, quickCaptureSource: Binding<QuickCaptureSource>,
        showingSettings: Binding<Bool>, showingAddTask: Binding<Bool>, effectiveScheme: ColorScheme,
        @ViewBuilder content: () -> Content
    ) {
        self.store = store
        self._selectedTab = selectedTab
        self._quickCaptureSource = quickCaptureSource
        self._showingSettings = showingSettings
        self._showingAddTask = showingAddTask
        self.effectiveScheme = effectiveScheme
        self.content = content()
    }

    private var todayFormatted: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        f.timeZone = .current
        return f.string(from: Date())
    }

    var body: some View {
        HSplitView {
            if !sidebarCollapsed {
                SidebarView(
                    store: store, selectedTab: $selectedTab, quickCaptureSource: $quickCaptureSource,
                    isCollapsed: $sidebarCollapsed, showingSettings: $showingSettings,
                    showingAddTask: $showingAddTask, showingQuickAdd: $showingQuickAdd,
                    effectiveScheme: effectiveScheme
                )
                .frame(
                    minWidth: Theme.sidebarMinWidth, idealWidth: Theme.sidebarIdealWidth,
                    maxWidth: Theme.sidebarMaxWidth, maxHeight: .infinity
                )
            }

            VStack(spacing: 0) {
                topBar
                content
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if sidebarCollapsed {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { sidebarCollapsed = false }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 15))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text(todayFormatted)
                .font(.system(size: Theme.sectionHeadingSize, weight: Theme.headingWeight))

            Spacer()

            // Pin-on-top — unaffected by this redesign, just relocated here
            // (was the top bar's leading icon, alongside the now-relocated
            // gear) since Settings' gear moved to the sidebar's bottom.
            Button {
                store.config.pinOnTop.toggle()
                store.config.save()
            } label: {
                Image(systemName: "mappin")
                    .font(.system(size: 15))
                    .foregroundStyle(store.config.pinOnTop ? Theme.accentBright : Theme.secondaryText(effectiveScheme))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            AppearanceSwitcher(store: store, effectiveScheme: effectiveScheme)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .foregroundStyle(Theme.primary(effectiveScheme))
    }
}
#endif
