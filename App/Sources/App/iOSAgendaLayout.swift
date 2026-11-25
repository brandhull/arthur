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
    @Binding var showingSettings: Bool
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
    // Starts closed on every launch (the app opens into Quick Capture).
    @State private var sidebarCollapsed = true
    // Transient, not persisted — a drawer starts closed every time, same as
    // any standard hamburger menu.
    @State private var showingDrawer = false
    // Horizontal finger travel while dragging the drawer open (positive) or
    // closed (negative); nil when no drag is in progress.
    @State private var drawerDragX: CGFloat?
    private let edgeGrabWidth: CGFloat = 20

    private func drawerProgress(width: CGFloat) -> CGFloat {
        guard let x = drawerDragX else { return showingDrawer ? 1 : 0 }
        let p = showingDrawer ? 1 + x / width : x / width
        return max(0, min(1, p))
    }

    /// Drag from the left edge to open, drag the open panel to close.
    private func drawerGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { v in
                // Only horizontal intent counts, so vertical scrolling is left alone.
                guard drawerDragX != nil || abs(v.translation.width) > abs(v.translation.height) else { return }
                drawerDragX = showingDrawer ? min(0, v.translation.width) : max(0, v.translation.width)
            }
            .onEnded { v in
                guard drawerDragX != nil else { return }
                let open: Bool
                if showingDrawer {
                    open = !(v.translation.width < -width * 0.3 || v.predictedEndTranslation.width < -width * 0.5)
                } else {
                    open = v.translation.width > width * 0.35 || v.predictedEndTranslation.width > width * 0.5
                }
                withAnimation(.easeOut(duration: 0.2)) {
                    showingDrawer = open
                    drawerDragX = nil
                }
            }
    }

    init(
        store: TaskStore, selectedTab: Binding<HomeTab>,
        showingSettings: Binding<Bool>,
        isPreviewing: Binding<Bool>, previewAvailable: Bool,
        effectiveScheme: ColorScheme, @ViewBuilder content: () -> Content
    ) {
        self.store = store
        self._selectedTab = selectedTab
        self._showingSettings = showingSettings
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
                            store: store, selectedTab: $selectedTab,
                            isCollapsed: $sidebarCollapsed, showingSettings: $showingSettings,
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

                    let drawerWidth = geo.size.width * 0.75
                    let progress = drawerProgress(width: drawerWidth)

                    // A thin strip along the left edge: grab it and drag right.
                    // Always in the tree (the drawer is drawn above it), so the
                    // gesture isn't cancelled when the drawer appears mid-drag.
                    Color.clear
                        .frame(width: edgeGrabWidth)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(drawerGesture(width: drawerWidth))

                    if progress > 0 {
                        iOSSidebarDrawer(
                            selectedTab: $selectedTab,
                            showingSettings: $showingSettings, isPresented: $showingDrawer,
                            width: drawerWidth, progress: progress, effectiveScheme: effectiveScheme
                        )
                        .simultaneousGesture(drawerGesture(width: drawerWidth))
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
                    .frame(width: 34, height: 44)
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
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)

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
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)

            Spacer()

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
