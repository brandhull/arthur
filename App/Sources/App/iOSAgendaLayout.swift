#if os(iOS)
import SwiftUI
import ArthurKit

/// iOS root layout — replaces AgendaView's old dropdown+floating-"+" iosBody.
/// Three shapes depending on device/orientation:
///   - iPhone: hamburger-triggered drawer (iOSSidebarDrawer), quick-add is
///     AgendaView's floating button (not part of this layout).
///   - iPad portrait: same drawer as iPhone, but with a quick-add button in
///     this layout's own top bar instead of a floating one.
///   - iPad landscape: persistent, collapsible, Mac-styled sidebar
///     (iPadLandscapeSidebar) instead of a drawer — Brandon's explicit ask
///     for "the same visual layout as the Mac app" once there's room for it.
/// Landscape is detected via GeometryReader (width > height), not device-
/// orientation APIs — more robust under Slide Over/Stage Manager, and the
/// codebase has no existing orientation-handling code to conflict with.
struct iOSAgendaLayout<Content: View>: View {
    @ObservedObject var store: TaskStore
    @Binding var selectedTab: HomeTab
    @Binding var quickCaptureSource: QuickCaptureSource
    @Binding var showingSettings: Bool
    @Binding var showingAddTask: Bool
    @Binding var showingQuickAdd: Bool
    /// Markdown preview toggle for the capture screens — the button only
    /// shows while one of them is on screen (`previewAvailable`).
    @Binding var isPreviewing: Bool
    let previewAvailable: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let effectiveScheme: ColorScheme
    let content: Content

    // Shared AppStorage key with Mac's MacAgendaLayout — deliberate reuse,
    // not an oversight: UserDefaults.standard is already local-only per
    // device, so there's no cross-device sync concern, and there's no
    // reason for iPad's landscape sidebar to remember collapse state
    // separately from what Mac would use on the same account.
    @AppStorage("sidebarCollapsed") private var sidebarCollapsed = false
    // Transient, not persisted — a drawer starts closed every time, same as
    // any standard hamburger menu.
    @State private var showingDrawer = false

    init(
        store: TaskStore, selectedTab: Binding<HomeTab>, quickCaptureSource: Binding<QuickCaptureSource>,
        showingSettings: Binding<Bool>, showingAddTask: Binding<Bool>, showingQuickAdd: Binding<Bool>,
        isPreviewing: Binding<Bool>, previewAvailable: Bool,
        effectiveScheme: ColorScheme, @ViewBuilder content: () -> Content
    ) {
        self.store = store
        self._selectedTab = selectedTab
        self._quickCaptureSource = quickCaptureSource
        self._showingSettings = showingSettings
        self._showingAddTask = showingAddTask
        self._showingQuickAdd = showingQuickAdd
        self._isPreviewing = isPreviewing
        self.previewAvailable = previewAvailable
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
        GeometryReader { geo in
            let isLandscapeIPad = horizontalSizeClass == .regular && geo.size.width > geo.size.height

            if isLandscapeIPad {
                HStack(spacing: 0) {
                    if !sidebarCollapsed {
                        iPadLandscapeSidebar(
                            store: store, selectedTab: $selectedTab, quickCaptureSource: $quickCaptureSource,
                            isCollapsed: $sidebarCollapsed, showingSettings: $showingSettings,
                            showingAddTask: $showingAddTask, showingQuickAdd: $showingQuickAdd,
                            effectiveScheme: effectiveScheme
                        )
                        .padding(.vertical, Theme.sidebarCardInset)
                        .padding(.leading, Theme.sidebarCardInset)
                        .padding(.trailing, Theme.sidebarCardInset / 2)
                    }

                    VStack(spacing: 0) {
                        landscapeTopBar
                        content
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Theme.background(effectiveScheme))
            } else {
                ZStack(alignment: .leading) {
                    VStack(spacing: 0) {
                        portraitTopBar
                        content
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showingDrawer {
                        iOSSidebarDrawer(
                            selectedTab: $selectedTab, quickCaptureSource: $quickCaptureSource,
                            showingSettings: $showingSettings, isPresented: $showingDrawer,
                            width: geo.size.width * 0.75, effectiveScheme: effectiveScheme
                        )
                        .transition(.move(edge: .leading))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showingDrawer)
                .background(Theme.background(effectiveScheme))
            }
        }
    }

    /// Same footprint as the appearance button beside it; only present while
    /// a capture screen with something to preview is showing.
    @ViewBuilder
    private var previewButton: some View {
        if previewAvailable {
            Button {
                isPreviewing.toggle()
            } label: {
                Image(systemName: isPreviewing ? "eye.fill" : "eye")
                    .font(.system(size: 18))
                    .foregroundStyle(isPreviewing ? Theme.accentBright : Theme.primary(effectiveScheme))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPreviewing ? "Back to editing" : "Preview markdown")
        }
    }

    private var landscapeTopBar: some View {
        HStack(spacing: 10) {
            if sidebarCollapsed {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { sidebarCollapsed = false }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: Theme.menuIconSize))
                        .frame(width: Theme.menuIconFrame, height: Theme.menuIconFrame)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text(todayFormatted)
                .font(.system(size: Theme.sectionHeadingSize, weight: Theme.headingWeight))

            Spacer()

            previewButton

            AppearanceCycleButton(store: store, effectiveScheme: effectiveScheme)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .foregroundStyle(Theme.primary(effectiveScheme))
    }

    private var portraitTopBar: some View {
        HStack(spacing: 10) {
            Button {
                showingDrawer = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: Theme.topBarIconSize))
                    .frame(width: Theme.topBarIconFrame, height: Theme.topBarIconFrame)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(todayFormatted)
                .font(.system(size: Theme.sectionHeadingSize, weight: Theme.headingWeight))

            Spacer()

            // iPad portrait only — iPhone's quick-add is AgendaView's
            // floating button instead, per Brandon's explicit split.
            // Presentation lives at AgendaView's top level now
            // (CenteredModal, mounted once, shared by every platform) — this
            // button just flips the shared showingQuickAdd flag instead of
            // anchoring its own popover.
            if horizontalSizeClass == .regular {
                Button {
                    showingQuickAdd = true
                } label: {
                    Image(systemName: "bubble.and.pencil")
                        .font(.system(size: Theme.topBarIconSize))
                        .frame(width: Theme.topBarIconFrame, height: Theme.topBarIconFrame)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            previewButton

            AppearanceCycleButton(store: store, effectiveScheme: effectiveScheme)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .foregroundStyle(Theme.primary(effectiveScheme))
    }
}
#endif
