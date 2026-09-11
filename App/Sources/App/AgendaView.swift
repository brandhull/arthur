import SwiftUI
import ArthurKit

/// Which of the four home-screen tabs is showing. Order matches Brandon's
/// explicit request: Rocks, Tasks, Quick Capture, then Reflection. No SF
/// Symbols for now — a deliberate simplification, not an oversight.
///
/// Search Baserow was a fifth tab here, removed once Brandon found he
/// wasn't using it at all — he's spinning Baserow browsing out into its own
/// separate app instead. Quick Capture's own Craft/Baserow toggle (pushing
/// a row into a table) is unrelated and stays; only the standalone
/// search-and-browse tab is gone.
enum HomeTab: String, CaseIterable, Identifiable {
    case rocks = "Rocks"
    case tasks = "Tasks"
    case quickCapture = "Quick Capture"
    case reflection = "Reflection"
    var id: String { rawValue }
}

struct AgendaView: View {
    @StateObject private var store = TaskStore()
    @StateObject private var documentStore = DocumentStore()
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var showingSettings = false
    @State private var showingAddTask = false
    // Shared by iPhone's floating quick-add button and iPad's top-bar/
    // sidebar quick-add button — only one of the three is ever actually
    // mounted at a time depending on device/orientation, so one Bool is
    // enough; see iOSAgendaLayout for the device/orientation branching.
    @State private var showingQuickAdd = false
    // Opens straight to Quick Capture, not Rocks — Brandon: Quick Capture
    // (with Craft, its own default source) is "90% of what I use Arthur
    // for," so that's what should be waiting right after the splash screen
    // rather than an extra tap away.
    @State private var selectedTab: HomeTab = .quickCapture
    // Owns Quick Capture's Craft/Baserow selection here (not internal to
    // QuickCaptureView) so the sidebar's/drawer's nested Craft/Baserow rows
    // can drive it identically on every platform.
    @State private var quickCaptureSource: QuickCaptureSource = .craft

    private var effectiveScheme: ColorScheme {
        switch store.config.appearance {
        case .system: return systemScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        Group {
            #if os(macOS)
            MacAgendaLayout(
                store: store, selectedTab: $selectedTab, quickCaptureSource: $quickCaptureSource,
                showingSettings: $showingSettings, showingAddTask: $showingAddTask,
                effectiveScheme: effectiveScheme
            ) {
                tabContent
            }
            #else
            ZStack(alignment: .bottomTrailing) {
                iOSAgendaLayout(
                    store: store, selectedTab: $selectedTab, quickCaptureSource: $quickCaptureSource,
                    showingSettings: $showingSettings, showingAddTask: $showingAddTask,
                    showingQuickAdd: $showingQuickAdd, effectiveScheme: effectiveScheme
                ) {
                    tabContent
                }

                // iPhone only — iPad gets its own non-floating quick-add
                // button instead (top bar in portrait, sidebar top row in
                // landscape — see iOSAgendaLayout). 32 horizontal — Brandon:
                // it was resting right on the ContentBox's own border
                // lines back when content had borders; kept for visual
                // continuity even though content is borderless now. Bottom
                // is taller (100, not 32) specifically to clear Quick
                // Capture's collapsed Destination card sitting right above
                // it — at 32 the button's top edge overlapped the card's
                // own expand/collapse chevron.
                if horizontalSizeClass == .compact {
                    floatingAddButton
                        .padding(.horizontal, 32)
                        .padding(.bottom, 100)
                }
            }
            #endif
        }
        .background(Theme.background(effectiveScheme))
        .preferredColorScheme(store.config.appearance == .system ? nil : effectiveScheme)
        #if os(macOS)
        .pinnedOnTop(store.config.pinOnTop)
        #endif
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store, documentStore: documentStore)
        }
        .sheet(isPresented: $showingAddTask) {
            AddTaskSheet(store: store)
        }
        .task {
            await store.refreshIfStale()
            documentStore.refreshIfStale(craftLink: store.config.craftLink)
        }
        // Brandon leaves Arthur open all day in one focused window, so
        // neither the cold-launch `.task` above nor the scenePhase-driven
        // refresh below (which only fires on an actual refocus) reliably
        // catches a document he created in Craft a few hours into that
        // session — nothing was polling in the background. This loop runs
        // for as long as AgendaView itself is alive (the app's whole
        // lifetime), independent of window focus. Uses `documentStore
        // .refresh` directly, not `refreshIfStale` — the 30-minute sleep
        // already is the staleness gate, no need to layer another one.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                documentStore.refresh(craftLink: store.config.craftLink)
            }
        }
        // `.task` only fires once per view lifecycle (cold launch), not when
        // resuming from the background — without this, "open the app" after
        // switching away and back would silently show stale data until a
        // manual pull-to-refresh. `onChange` doesn't fire for the initial
        // value, so this can't double-fetch alongside the `.task` above.
        //
        // Goes through refreshIfStale, not a direct refresh — on Mac,
        // scenePhase flips to .active on every window refocus, not just a
        // real return from the background the way it does on iOS. Arthur's
        // meant to stay open all day and get alt-tabbed into constantly, so
        // an unconditional three-call refetch here was firing on nearly
        // every click back into the window. The staleness gate (90s)
        // collapses that down to "at most once every 90 seconds," which
        // still means a real return-after-a-while gets fresh data.
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                Task { await store.refreshIfStale() }
                documentStore.refreshIfStale(craftLink: store.config.craftLink)
            }
        }
        .refreshable {
            // Same gap as Settings' Force Sync button — pull-to-refresh
            // only ever covered TaskStore's own data, never the document
            // list Quick Capture searches against.
            documentStore.refresh(craftLink: store.config.craftLink)
            await store.forceSync()
        }
        .alert("Something went wrong", isPresented: .constant(store.errorMessage != nil), actions: {
            Button("OK") { store.errorMessage = nil }
        }, message: {
            Text(store.errorMessage ?? "")
        })
    }

    /// All four tabs stay mounted (opacity-swapped, not conditionally
    /// created/destroyed) so switching tabs never loses in-progress state —
    /// a partially-typed Quick Capture note or an in-progress task edit
    /// survives a trip to another tab and back, the same way a native
    /// TabView keeps its tabs alive in the background. Built exactly once
    /// here and handed to every platform's chrome (MacAgendaLayout's main
    /// pane, iOSAgendaLayout's main pane) so there's a single place that
    /// ever instantiates these four views — no redesign should grow a
    /// second, similar-looking copy that can drift out of sync.
    private var tabContent: some View {
        ZStack {
            RocksView(store: store)
                .opacity(selectedTab == .rocks ? 1 : 0)
                .allowsHitTesting(selectedTab == .rocks)
            TasksView(store: store)
                .opacity(selectedTab == .tasks ? 1 : 0)
                .allowsHitTesting(selectedTab == .tasks)
            QuickCaptureView(
                store: store, documentStore: documentStore, source: $quickCaptureSource,
                isActive: selectedTab == .quickCapture
            )
                .opacity(selectedTab == .quickCapture ? 1 : 0)
                .allowsHitTesting(selectedTab == .quickCapture)
            ReflectionView(store: store)
                .opacity(selectedTab == .reflection ? 1 : 0)
                .allowsHitTesting(selectedTab == .reflection)
        }
    }

    #if os(iOS)
    /// iPhone-only floating quick-add button (iPad uses a non-floating
    /// button instead — see iOSAgendaLayout). Same circle/shadow/position
    /// as the app's old "+" button; icon is now bubble.and.pencil and it
    /// opens the same QuickAddModal Mac uses (New Task / Quick Capture /
    /// inline New Reflection) instead of a plain 3-item Menu — `.popover`
    /// auto-adapts into a bottom sheet on iPhone's compact width, which is
    /// exactly right for the inline New Reflection compose box.
    private var floatingAddButton: some View {
        Button {
            showingQuickAdd = true
        } label: {
            Image(systemName: "bubble.and.pencil")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(effectiveScheme == .dark ? Color.black : Color.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Theme.primary(effectiveScheme)))
                .shadow(color: Color.black.opacity(0.25), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingQuickAdd) {
            QuickAddModal(
                store: store, selectedTab: $selectedTab,
                showingAddTask: $showingAddTask, isPresented: $showingQuickAdd
            )
        }
    }
    #endif
}
