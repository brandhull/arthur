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
    case rocks = "Rocks"
    case bits = "Bits"
    case tasks = "Tasks"
    case quickCapture = "Quick Capture"
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
    @State private var showingAddTask = false
    // "Document" quick-add flow — a new Craft page in a chosen folder, not
    // part of the sidebar/drawer nav yet (Brandon: "for now"), reachable
    // only via the quick-add popup's Document row.
    @State private var showingDocumentCapture = false
    // "Bits" quick-add flow — a blank capture screen that saves a new Bit,
    // reachable only via the quick-add popup's Bits row. Same embedded-layer
    // treatment as Document.
    @State private var showingBitCapture = false
    // "Reflection" quick-add flow — a blank capture screen that appends to
    // today's daily note.
    @State private var showingReflectionCapture = false
    // Top-bar markdown preview toggle, shared by Quick Capture (Craft),
    // New Document, and New Reflection. Reset whenever the visible screen
    // changes (see previewScreenID) so a preview never carries over.
    @State private var isPreviewing = false
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
    // Lifted out of QuickCaptureView (was purely local @State there) so the
    // iPhone floating quick-add button can hide itself while the card's
    // expanded — Brandon: the button sitting right where the expanded
    // Destination card's own content now is looked wrong/cluttered.
    @State private var isDestinationExpanded = false
    #if os(iOS)
    // True while the software keyboard is up — the iPhone floating button
    // hides then, since you're typing and it only takes up room.
    @State private var keyboardVisible = false
    #endif

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
                showingQuickAdd: $showingQuickAdd,
                isPreviewing: $isPreviewing, previewAvailable: previewAvailable,
                effectiveScheme: effectiveScheme
            ) {
                tabContent
            }
            #else
            ZStack(alignment: .bottomTrailing) {
                iOSAgendaLayout(
                    store: store, selectedTab: $selectedTab, quickCaptureSource: $quickCaptureSource,
                    showingSettings: $showingSettings, showingAddTask: $showingAddTask,
                    showingQuickAdd: $showingQuickAdd,
                    isPreviewing: $isPreviewing, previewAvailable: previewAvailable,
                    effectiveScheme: effectiveScheme
                ) {
                    tabContent
                }

                // iPhone only — iPad gets its own non-floating quick-add
                // button instead (top bar in portrait, sidebar top row in
                // landscape — see iOSAgendaLayout). 32 horizontal — Brandon:
                // it was resting right on the ContentBox's own border
                // lines back when content had borders; kept for visual
                // continuity even though content is borderless now. Bottom
                // is taller (68, not 32) specifically to clear Quick
                // Capture's collapsed Destination card sitting right above
                // it, resting just slightly above it — at 32 the button
                // overlapped the card's own expand/collapse chevron; 100
                // (an earlier attempt) left it floating too high above the
                // card instead.
                if horizontalSizeClass == .compact {
                    floatingAddButton
                        .padding(.horizontal, 32)
                        .padding(.bottom, 68)
                        // Hidden while Quick Capture's Destination card is
                        // expanded — Brandon: with the card's own picker/
                        // Save content now taking up that space, the button
                        // sitting right on top of it read as cluttered.
                        // Only relevant on the Quick Capture tab with Craft
                        // selected (Baserow's form and every other tab
                        // don't have a Destination card at all).
                        .opacity(isFloatingButtonHidden ? 0 : 1)
                        .allowsHitTesting(!isFloatingButtonHidden)
                        .animation(.easeInOut(duration: 0.15), value: isFloatingButtonHidden)
                }
            }
            #endif
        }
        .background(Theme.background(effectiveScheme))
        // Mounted once here (not per-button) so it centers over the entire
        // window/screen on every platform — Mac's sidebar, iPad's landscape
        // sidebar/portrait top bar, and iPhone's floating button all just
        // flip this same showingQuickAdd flag now instead of each anchoring
        // its own popover in a different spot with different fonts.
        .overlay {
            CenteredModal(isPresented: $showingQuickAdd, effectiveScheme: effectiveScheme, anchor: quickAddAnchor) {
                QuickAddModal(
                    store: store, selectedTab: $selectedTab,
                    showingAddTask: $showingAddTask, showingDocumentCapture: $showingDocumentCapture,
                    showingBitCapture: $showingBitCapture, showingReflectionCapture: $showingReflectionCapture,
                    isPresented: $showingQuickAdd
                )
            }
        }
        .preferredColorScheme(store.config.appearance == .system ? nil : effectiveScheme)
        #if os(macOS)
        .pinnedOnTop(store.config.pinOnTop)
        #else
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
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
    /// The corner the quick-add card grows out of: toward the floating button
    /// on iPhone (bottom right), toward the sidebar button on Mac (top
    /// left), and the top edge on iPad, where the button sits in the top bar.
    private var quickAddAnchor: UnitPoint {
        #if os(iOS)
        return horizontalSizeClass == .compact ? .bottomTrailing : .top
        #else
        return .topLeading
        #endif
    }

    /// Whether the visible screen has markdown to preview: Quick Capture's
    /// Craft side, New Document, or New Reflection. (Bits are plain text for
    /// Baserow, and Quick Capture's Baserow form has no free-form markdown.)
    private var previewAvailable: Bool {
        if showingDocumentCapture || showingReflectionCapture { return true }
        if showingBitCapture { return false }
        return selectedTab == .quickCapture && quickCaptureSource == .craft
    }

    /// Changes whenever the visible screen does, so the preview toggle can
    /// switch itself off instead of leaking onto the next screen.
    private var previewScreenID: String {
        "\(selectedTab.rawValue)|\(quickCaptureSource.rawValue)|\(showingDocumentCapture)|\(showingBitCapture)|\(showingReflectionCapture)"
    }

    private var tabContent: some View {
        ZStack {
            RocksView(store: store)
                .opacity(selectedTab == .rocks && !coverShowing ? 1 : 0)
                .allowsHitTesting(selectedTab == .rocks && !coverShowing)
                .disabled(!(selectedTab == .rocks && !coverShowing))
            BitsView(store: store, bits: bits, isActive: selectedTab == .bits && !coverShowing)
                .opacity(selectedTab == .bits && !coverShowing ? 1 : 0)
                .allowsHitTesting(selectedTab == .bits && !coverShowing)
                .disabled(!(selectedTab == .bits && !coverShowing))
            TasksView(store: store)
                .opacity(selectedTab == .tasks && !coverShowing ? 1 : 0)
                .allowsHitTesting(selectedTab == .tasks && !coverShowing)
                .disabled(!(selectedTab == .tasks && !coverShowing))
            QuickCaptureView(
                store: store, documentStore: documentStore, outbox: outbox, source: $quickCaptureSource,
                isActive: selectedTab == .quickCapture, isPreviewing: isPreviewing,
                isDestinationExpanded: $isDestinationExpanded
            )
                .opacity(selectedTab == .quickCapture && !coverShowing ? 1 : 0)
                .allowsHitTesting(selectedTab == .quickCapture && !coverShowing)
                .disabled(!(selectedTab == .quickCapture && !coverShowing))
            ReflectionView(store: store)
                .opacity(selectedTab == .reflection && !coverShowing ? 1 : 0)
                .allowsHitTesting(selectedTab == .reflection && !coverShowing)
                .disabled(!(selectedTab == .reflection && !coverShowing))
            DocumentCaptureSheet(store: store, isPresented: $showingDocumentCapture, isPreviewing: isPreviewing)
                .opacity(showingDocumentCapture ? 1 : 0)
                .allowsHitTesting(showingDocumentCapture)
                .disabled(!(showingDocumentCapture))
            TextCaptureView(
                store: store, isPresented: $showingBitCapture,
                save: { text in
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
                onSaved: { selectedTab = .bits }
            )
                .opacity(showingBitCapture ? 1 : 0)
                .allowsHitTesting(showingBitCapture)
                .disabled(!(showingBitCapture))
            TextCaptureView(
                store: store, isPresented: $showingReflectionCapture,
                save: { text in
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
                onSaved: { selectedTab = .reflection },
                isPreviewing: isPreviewing
            )
                .opacity(showingReflectionCapture ? 1 : 0)
                .allowsHitTesting(showingReflectionCapture)
                .disabled(!(showingReflectionCapture))
        }
        // Picking any real destination while Document is showing dismisses
        // it, the same way selecting any other tab always shows that tab —
        // without this, tapping e.g. Rocks in the sidebar while Document is
        // up would do nothing visible (Document has no HomeTab case to lose
        // to). Doesn't cover re-tapping whatever tab was already selected
        // underneath (onChange only fires on an actual value change) — the
        // X button in Document itself is the fallback for that.
        .onChange(of: selectedTab) { showingDocumentCapture = false; showingBitCapture = false; showingReflectionCapture = false }
        .onChange(of: quickCaptureSource) { showingDocumentCapture = false; showingBitCapture = false; showingReflectionCapture = false }
        .onChange(of: previewScreenID) { isPreviewing = false }
        .overlay(alignment: .bottomLeading) { OutboxBadge(outbox: outbox, scheme: effectiveScheme) }
        .task {
            outbox.configProvider = { store.config }
            outbox.onDelivered = { kinds in
                Task { @MainActor in
                    if kinds.contains(.bit) { await bits.load(store.config) }
                    if kinds.contains(.reflection) { await store.loadDailyNote() }
                }
            }
            await outbox.drain()
        }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await outbox.drain() } } }
    }

    /// Document, Bits and Reflection capture are full-pane layers over whichever tab is
    /// selected; while either shows, every real tab is hidden.
    private var coverShowing: Bool { showingDocumentCapture || showingBitCapture || showingReflectionCapture }

    #if os(iOS)
    private var isFloatingButtonHidden: Bool {
        (selectedTab == .quickCapture && quickCaptureSource == .craft && isDestinationExpanded)
            // Every capture screen's Save button sits where this floating
            // button does.
            || coverShowing
            // And while typing anywhere, so it isn't in the way.
            || keyboardVisible
    }

    /// iPhone-only floating quick-add button (iPad uses a non-floating
    /// button instead — see iOSAgendaLayout). Same circle/shadow/position
    /// as the app's old "+" button; icon is bubble.and.pencil. Presentation
    /// lives at AgendaView's top level now (CenteredModal, mounted once,
    /// shared by every platform) — this button just flips the shared
    /// showingQuickAdd flag instead of anchoring its own popover (which
    /// used to auto-adapt into a bottom sheet here specifically, one of the
    /// three different presentations Brandon asked to standardize).
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
    }
    #endif
}
