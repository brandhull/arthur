#if os(macOS)
import SwiftUI
import ArthurKit

/// Mac-only root layout — Notion/Maverick-style collapsible, resizable
/// sidebar (ResizableHSplit, a custom NSSplitViewController wrapper — not
/// SwiftUI's own HSplitView, whose divider can't be hidden/restyled, and
/// not NavigationSplitView, whose sidebar column needs custom chrome — a
/// quick-add button, a gear pinned to the bottom, nested Quick Capture rows
/// — that its system-owned collapse/toolbar model doesn't cleanly
/// accommodate) plus one main content pane. Replaces AgendaView's old
/// dropdown+floating-"+"-button chrome on Mac only; iOS/iPadOS keep that
/// layout entirely, unchanged, via AgendaView's own `#if os(macOS)` branch.
struct MacAgendaLayout<Content: View>: View {
    @ObservedObject var store: TaskStore
    @Binding var selectedTab: HomeTab
    @Binding var quickCaptureSource: QuickCaptureSource
    @Binding var showingSettings: Bool
    @Binding var showingAddTask: Bool
    @Binding var showingQuickAdd: Bool
    let effectiveScheme: ColorScheme
    let content: Content

    // Pure Mac window-chrome prefs — deliberately @AppStorage, not part of
    // the cross-device Config/iCloud-KVS system: nothing here needs to sync
    // across devices, and mixing single-window layout state into Config
    // would just add sync-conflict surface for no benefit.
    @AppStorage("sidebarCollapsed") private var sidebarCollapsed = false

    init(
        store: TaskStore, selectedTab: Binding<HomeTab>, quickCaptureSource: Binding<QuickCaptureSource>,
        showingSettings: Binding<Bool>, showingAddTask: Binding<Bool>, showingQuickAdd: Binding<Bool>,
        effectiveScheme: ColorScheme,
        @ViewBuilder content: () -> Content
    ) {
        self.store = store
        self._selectedTab = selectedTab
        self._quickCaptureSource = quickCaptureSource
        self._showingSettings = showingSettings
        self._showingAddTask = showingAddTask
        self._showingQuickAdd = showingQuickAdd
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
        ResizableHSplit(
            isCollapsed: $sidebarCollapsed,
            leadingMinWidth: Theme.sidebarMinWidth, leadingIdealWidth: Theme.sidebarIdealWidth,
            leadingMaxWidth: Theme.sidebarMaxWidth
        ) {
            // The ZStack's own background fills the whole pane the split
            // controller hands this child — an NSSplitViewItem's pane
            // otherwise paints its own default fill underneath our SwiftUI
            // content, which would show through the inset gap instead of
            // Arthur's own background. Painting it explicitly here, then
            // floating the rounded, distinctly-colored, thin-bordered
            // sidebar card on top with a margin on three sides (not the
            // trailing edge, which abuts the — now invisible — divider), is
            // what gives the "inset, floating over the window" look from
            // Brandon's Maverick reference, right down to Maverick's own
            // thin hairline border replacing what would otherwise be a
            // harsh black divider line.
            ZStack(alignment: .topLeading) {
                Theme.background(effectiveScheme)
                SidebarView(
                    store: store, selectedTab: $selectedTab, quickCaptureSource: $quickCaptureSource,
                    isCollapsed: $sidebarCollapsed, showingSettings: $showingSettings,
                    showingAddTask: $showingAddTask, showingQuickAdd: $showingQuickAdd,
                    effectiveScheme: effectiveScheme
                )
                .background(
                    RoundedRectangle(cornerRadius: Theme.sidebarCardCornerRadius, style: .continuous)
                        .fill(Theme.sidebarCardBackground(effectiveScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.sidebarCardCornerRadius, style: .continuous)
                        .stroke(Theme.primary(effectiveScheme).opacity(Theme.borderOpacity), lineWidth: Theme.borderWidth)
                )
                .padding(.top, Theme.sidebarCardInset)
                .padding(.bottom, Theme.sidebarCardInset)
                .padding(.leading, Theme.sidebarCardInset)
                .padding(.trailing, Theme.sidebarCardInset / 2)
            }
        } trailing: {
            VStack(spacing: 0) {
                topBar
                content
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background(effectiveScheme))
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
