import SwiftUI
import ArthurKit

/// Which of the home-screen tabs is showing. Order matches Brandon's
/// explicit request: Rocks, Tasks, Quick Capture, Reflection, then Search
/// Craft. No SF Symbols for now — a deliberate simplification, not an
/// oversight.
///
/// Search Baserow used to be a fifth tab here, removed once Brandon found he
/// wasn't using it at all — he's spinning Baserow browsing out into its own
/// separate app instead. Quick Capture's own Craft/Baserow toggle (pushing
/// a row into a table) is unrelated and stays; only that standalone
/// search-and-browse tab was gone. (A "Search Craft" Q&A tab existed too, and
/// was removed in 1.2.0.)
enum HomeTab: String, CaseIterable, Identifiable {
    case quickCapture = "Quick Capture"
    case rocks = "Rocks"
    case bits = "Bits"
    case tasks = "Tasks"
    case reflection = "Reflection"
    var id: String { rawValue }
}

struct AgendaView: View {
    @StateObject private var store = TaskStore()
    @StateObject private var documentStore = DocumentStore()
    @StateObject private var bits = BitsStore()
    @StateObject private var outbox = OutboxStore()
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var showingSettings = false
    @EnvironmentObject private var draft: QuickCaptureDraft
    // Where capture goes (Craft page, new page, Reflection, Bits, task,
    // Baserow) is chosen in Quick Capture's own Destination card; there are
    // no separate "New" buttons or capture screens anymore.
    //
    // Top-bar markdown preview toggle (Quick Capture's Craft page / new page /
    // Reflection targets). Reset whenever the visible screen or target
    // changes (see previewScreenID) so a preview never carries over.
    @State private var isPreviewing = false
    // Opens straight to Quick Capture — "90% of what I use Arthur for," so
    // that's what waits right after the splash screen.
    @State private var selectedTab: HomeTab = .quickCapture
    // Whether Quick Capture's Destination card is expanded (owned here, passed
    // down, so it survives view updates).
    @State private var isDestinationExpanded = false

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
                store: store, selectedTab: $selectedTab,
                showingSettings: $showingSettings,
                isPreviewing: $isPreviewing, previewAvailable: previewAvailable,
                effectiveScheme: effectiveScheme
            ) {
                tabContent
            }
            #else
            iOSAgendaLayout(
                store: store, selectedTab: $selectedTab,
                showingSettings: $showingSettings,
                isPreviewing: $isPreviewing, previewAvailable: previewAvailable,
                effectiveScheme: effectiveScheme
            ) {
                tabContent
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
            await bits.load(store.config)
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
    ///
    /// Document is a fifth layer here, same opacity-swap treatment, even
    /// though it isn't a real HomeTab/sidebar row — Brandon's correction
    /// after an earlier attempt covered the whole window (sidebar/hamburger
    /// included) in a full-window overlay/fullScreenCover: he still needs
    /// the sidebar or hamburger menu reachable while Document is showing,
    /// exactly like every other tab. Embedding it here, inside whatever
    /// MacAgendaLayout/iOSAgendaLayout's own chrome already wraps `content`
    /// in, is what keeps that chrome visible. showingDocumentCapture drives
    /// its visibility directly (not selectedTab, since Document has no
    /// HomeTab case of its own); picking any real sidebar/drawer
    /// destination while it's showing dismisses it via the onChange below.
    /// Whether the visible screen has markdown to preview: Quick Capture
    /// while it's pointed at a Craft page, a new Craft page, or Reflection.
    /// (Bits and tasks are plain text; Baserow is a form.)
    private var previewAvailable: Bool {
        guard selectedTab == .quickCapture else { return false }
        return [.page, .newPage, .reflection].contains(draft.target)
    }

    /// Changes whenever the visible screen does, so the preview toggle can
    /// switch itself off instead of leaking onto the next screen.
    private var previewScreenID: String {
        "\(selectedTab.rawValue)|\(draft.target.rawValue)"
    }

    private var tabContent: some View {
        ZStack {
            QuickCaptureView(
                store: store, documentStore: documentStore, outbox: outbox,
                saveBit: { text in
                    guard store.config.isBitsConfigured else { return "Choose your Bits table in Settings." }
                    if !outbox.isOnline {
                        outbox.enqueue(OutboxItem(kind: .bit, text: text))
                        return nil
                    }
                    if await bits.add(text: text, config: store.config) { return nil }
                    if bits.lastAddWasOffline {
                        outbox.enqueue(OutboxItem(kind: .bit, text: text))
                        return nil
                    }
                    return bits.errorMessage ?? "Couldn’t save that Bit."
                },
                saveReflection: { text in
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !outbox.isOnline && store.config.isConfigured {
                        outbox.enqueue(OutboxItem(kind: .reflection, text: trimmed, day: OutboxItem.todayString()))
                        return nil
                    }
                    let failure = await store.appendToDailyNote(text)
                    if failure != nil && store.lastAppendWasOffline {
                        outbox.enqueue(OutboxItem(kind: .reflection, text: trimmed, day: OutboxItem.todayString()))
                        return nil
                    }
                    return failure
                },
                isActive: selectedTab == .quickCapture, isPreviewing: isPreviewing,
                isDestinationExpanded: $isDestinationExpanded
            )
                .opacity(selectedTab == .quickCapture ? 1 : 0)
                .allowsHitTesting(selectedTab == .quickCapture)
                .disabled(selectedTab != .quickCapture)
            RocksView(store: store)
                .opacity(selectedTab == .rocks ? 1 : 0)
                .allowsHitTesting(selectedTab == .rocks)
                .disabled(selectedTab != .rocks)
            BitsView(store: store, bits: bits, isActive: selectedTab == .bits)
                .opacity(selectedTab == .bits ? 1 : 0)
                .allowsHitTesting(selectedTab == .bits)
                .disabled(selectedTab != .bits)
            TasksView(store: store)
                .opacity(selectedTab == .tasks ? 1 : 0)
                .allowsHitTesting(selectedTab == .tasks)
                .disabled(selectedTab != .tasks)
            ReflectionView(store: store)
                .opacity(selectedTab == .reflection ? 1 : 0)
                .allowsHitTesting(selectedTab == .reflection)
                .disabled(selectedTab != .reflection)
        }
        .onChange(of: previewScreenID) { isPreviewing = false }
        .overlay(alignment: .bottomLeading) { OutboxBadge(outbox: outbox, scheme: effectiveScheme) }
        .task {
            outbox.configProvider = { store.config }
            outbox.onDelivered = { kinds in
                Task { @MainActor in
                    if kinds.contains(.bit) { await bits.load(store.config) }
                    if kinds.contains(.reflection) { await store.loadDailyNote() }
                    if kinds.contains(.task) { await store.refresh() }
                }
            }
            await outbox.drain()
        }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await outbox.drain() } } }
    }
}
