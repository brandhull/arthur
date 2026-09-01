import SwiftUI
import ArthurKit

/// Which of the five home-screen tabs is showing. Order matches Brandon's
/// explicit request: Rocks, Tasks, Quick Capture, Reflection, then Search
/// Baserow last. No SF Symbols for now — a deliberate simplification, not
/// an oversight.
enum HomeTab: String, CaseIterable, Identifiable {
    case rocks = "Rocks"
    case tasks = "Tasks"
    case quickCapture = "Quick Capture"
    case reflection = "Reflection"
    case searchBaserow = "Search Baserow"
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
    @State private var showingAddNote = false
    @State private var selectedTab: HomeTab = .rocks

    private var effectiveScheme: ColorScheme {
        switch store.config.appearance {
        case .system: return systemScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// "August 6, 2026" — replaces the "Arthur" title text (the app itself
    /// keeps that name everywhere else — window title, Settings, etc. —
    /// just not this one heading). Recomputed on every render rather than
    /// cached, so it's still correct if the app is left open across
    /// midnight.
    private var todayFormatted: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        f.timeZone = .current
        return f.string(from: Date())
    }

    /// Bumped up on iPad's regular width — Brandon: on a much larger
    /// screen, the calendar/gear icons could stand to be a little bigger,
    /// not just the same size stretched across more space.
    private var topBarIconSize: CGFloat {
        #if os(iOS)
        return horizontalSizeClass == .regular ? 22 : 18
        #else
        return 18
        #endif
    }

    /// See the comment on the icon HStack that uses this.
    private var iconSpacing: CGFloat {
        #if os(macOS)
        return 10
        #else
        return 20
        #endif
    }

    private var tabFontSize: CGFloat {
        #if os(iOS)
        // 12 on compact (iPhone) used to be sized to fit 4-5 tab labels
        // side-by-side in the old folder-tab row — stale now that the
        // dropdown only ever shows one label at a time, with plenty of
        // horizontal room. Brandon: bump it up, but the box's own height/
        // padding (tabRowHeight, untouched here) is fine as-is.
        return horizontalSizeClass == .regular ? Theme.sectionHeadingSize : 16
        #else
        return Theme.sectionHeadingSize
        #endif
    }

    private var inputFontSize: CGFloat {
        #if os(iOS)
        return Theme.inputFontSize(horizontalSizeClass: horizontalSizeClass)
        #else
        return Theme.inputFontSize()
        #endif
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                topBar
                tabSelector
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 16)

                // All four tabs stay mounted (opacity-swapped, not
                // conditionally created/destroyed) so switching tabs never
                // loses in-progress state — a partially-typed Quick Capture
                // note or an in-progress task edit survives a trip to
                // another tab and back, the same way a native TabView keeps
                // its tabs alive in the background.
                ZStack {
                    RocksView(store: store)
                        .opacity(selectedTab == .rocks ? 1 : 0)
                        .allowsHitTesting(selectedTab == .rocks)
                    taskSection
                        .opacity(selectedTab == .tasks ? 1 : 0)
                        .allowsHitTesting(selectedTab == .tasks)
                    QuickCaptureView(store: store, documentStore: documentStore)
                        .opacity(selectedTab == .quickCapture ? 1 : 0)
                        .allowsHitTesting(selectedTab == .quickCapture)
                    ReflectionView(store: store)
                        .opacity(selectedTab == .reflection ? 1 : 0)
                        .allowsHitTesting(selectedTab == .reflection)
                    SearchBaserowView(store: store)
                        .opacity(selectedTab == .searchBaserow ? 1 : 0)
                        .allowsHitTesting(selectedTab == .searchBaserow)
                }
            }

            // 32, not 24 — Brandon: it was resting right on the ContentBox's
            // own border lines. Since this is a single uniform padding value
            // in a .bottomTrailing overlay, bumping it moves the button up
            // and to the left by the same amount in both directions.
            floatingAddButton
                .padding(32)
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
        .sheet(isPresented: $showingAddNote) {
            AddNoteSheet(store: store)
        }
        .task {
            await store.refreshIfStale()
            documentStore.refreshIfStale(craftLink: store.config.craftLink)
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

    /// A circle with a "+" — replaces every tab's own inline Add button.
    /// Tapping it opens a menu of the three things that can be quickly
    /// added; picking one either opens the same modal sheet that button
    /// used to (Task, Reflection) or switches to the Quick Capture tab
    /// (that one's a full tab now with its own Craft/Baserow toggle, not a
    /// modal, so there's nothing separate to open). Rocks isn't one of the
    /// three — it's edited in place via its own Edit button, not "added to."
    private var floatingAddButton: some View {
        Menu {
            Button("Task") { showingAddTask = true }
            Button("Reflection") { showingAddNote = true }
            Button("Quick Capture") { selectedTab = .quickCapture }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(effectiveScheme == .dark ? Color.black : Color.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Theme.primary(effectiveScheme)))
                .shadow(color: Color.black.opacity(0.25), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    /// Notion-style: left-aligned title at the same size as the tab
    /// dropdown text below it, so it reads as part of the same content
    /// column rather than a separate, oversized free-floating header bar.
    /// Was brandHeadingSize (up to 24pt) — Brandon flagged it as too large
    /// next to the rest of the UI and asked for it to match "the default
    /// used in the app," which this now does exactly by reusing tabFontSize
    /// rather than a separate size scale reserved just for this label.
    private var headerDateSize: CGFloat { tabFontSize }

    private var topBar: some View {
        HStack(spacing: 8) {
            Text(todayFormatted).font(.system(size: headerDateSize, weight: Theme.headingWeight))

            Spacer()

            // Own HStack with wider spacing than the rest of the bar — at
            // the default 8pt these two sat close enough that Brandon kept
            // fat-fingering Settings when aiming for the calendar (and vice
            // versa). Each icon also gets an explicit 44x44 tap target
            // (Apple's minimum recommended size) rather than just the bare
            // glyph's own small bounding box.
            //
            // Mac gets its own tighter value (10, half of iOS's 20) — the
            // pin/gear pair there doesn't have the fat-finger problem this
            // spacing was originally sized for (Mac has no touch targets to
            // avoid overlapping), and Brandon flagged the pin as reading too
            // far from the gear at the shared 20pt spacing.
            HStack(spacing: iconSpacing) {
                #if os(iOS)
                Button {
                    // Universal link, not the calshow:// scheme — Google
                    // Calendar (if installed) claims this domain and
                    // intercepts it, same as tapping a calendar.google.com
                    // link anywhere else on iOS; otherwise it falls through
                    // to the default browser. Chosen over calshow://
                    // specifically because that scheme always opens Apple's
                    // own Calendar, which isn't what Brandon uses.
                    guard let url = URL(string: "https://calendar.google.com") else { return }
                    Task { await UIApplication.shared.open(url) }
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: topBarIconSize))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                #endif
                #if os(macOS)
                // Mac only — no window-level equivalent on iOS/iPadOS. Was a
                // Settings toggle at first; Brandon: too many clicks for
                // something he'd want to flip often, and the calendar icon's
                // slot here is unused on Mac anyway. Brandon named the exact
                // symbol ("mappin", not a filled/circle variant) and didn't
                // want a text label — on/off state is conveyed by tint alone
                // (accent when pinned, secondary when not), same pattern as
                // the task checkbox's done/not-done color swap elsewhere.
                Button {
                    store.config.pinOnTop.toggle()
                    store.config.save()
                } label: {
                    Image(systemName: "mappin")
                        .font(.system(size: topBarIconSize))
                        .foregroundStyle(store.config.pinOnTop ? Theme.accentBright : Theme.secondaryText(effectiveScheme))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                #endif
                Button {
                    showingSettings = true
                } label: {
                    // A gear icon alone already reads as "Settings" — no need
                    // for button chrome around it (macOS's default Button
                    // style adds a visible bordered background; plain
                    // removes that on every platform). Settings itself is
                    // unchanged by this whole redesign — it's still where
                    // the Craft/Baserow connections live, same icon/position.
                    Image(systemName: "gearshape")
                        .font(.system(size: topBarIconSize))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .foregroundStyle(Theme.primary(effectiveScheme))
    }

    /// One dropdown on every platform/size class — used to be folder tabs
    /// on iPad (regular width) and Mac, dropping to this dropdown only on
    /// iPhone's compact width where four folder tabs didn't fit. Brandon
    /// caught, zoomed in on Mac, that the folder tabs' custom-drawn corner
    /// (an UnevenRoundedRectangle fill plus a separate hairline-opacity
    /// baseline Rectangle) never quite matched at the seam where they
    /// meet — the two strokes rendered as visibly different colors, with
    /// the vertical edge overshooting the horizontal one instead of closing
    /// exactly — and that resizing the Mac window made the tabs'
    /// .minimumScaleFactor kick in unevenly, so the four labels didn't even
    /// stay the same size as each other. iPad had the exact same folder-tab
    /// implementation and so the exact same problem, just not yet flagged —
    /// this is one single control everywhere now instead of four hand-drawn
    /// shapes that have to align, so there's no seam or scale-factor drift
    /// left to happen on any platform.
    private var tabSelector: some View {
        tabDropdown
    }

    /// A Binding<HomeTab?> adapter over `selectedTab` (never actually nil) —
    /// DropdownButton's selection is optional so it can also serve Search
    /// Baserow's Database/Table pickers, which genuinely start unselected.
    private var selectedTabBinding: Binding<HomeTab?> {
        Binding(get: { selectedTab }, set: { if let newValue = $0 { selectedTab = newValue } })
    }

    private var tabDropdown: some View {
        DropdownButton(
            items: HomeTab.allCases, label: { $0.rawValue }, selection: selectedTabBinding,
            placeholder: "", scheme: effectiveScheme,
            font: .system(size: tabFontSize, weight: Theme.headingWeight), height: tabRowHeight
        )
    }

    /// Fixed row height every tab shares — see the comment where this is
    /// applied for why a fixed height (not just padding) is needed for the
    /// tops to align. Theme.controlHeight, not a locally-owned value — the
    /// pill buttons match themselves to this same source now too.
    private var tabRowHeight: CGFloat {
        #if os(iOS)
        return Theme.controlHeight(horizontalSizeClass: horizontalSizeClass)
        #else
        return Theme.controlHeight()
        #endif
    }

    /// Bumped up on Mac specifically — Brandon flagged the filter labels as
    /// too small on a larger screen, same complaint as FieldLabel. iOS/
    /// iPadOS weren't flagged, so they keep their original size.
    private var filterFontSize: CGFloat {
        #if os(macOS)
        return 14
        #else
        return 13
        #endif
    }

    private var taskSection: some View {
        VStack(spacing: 0) {
            // No "Tasks" heading here — the tab bar shows that now, and the
            // Add button that used to sit at the trailing end of this row
            // is gone too — the floating "+" button covers that now, so
            // this row is just the filter pills.
            HStack(spacing: 10) {
                PillFilterBar(
                    items: TaskFilter.allCases, label: \.rawValue,
                    selection: $store.filter, scheme: effectiveScheme, fontSize: filterFontSize
                )
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: Theme.headerRowHeight)
            .foregroundStyle(Theme.primary(effectiveScheme))

            // Top padding matches Quick Capture's own FieldBox/FieldLabel
            // spacing below its header row — see RocksView's comment for
            // the full reasoning; same fix applied identically here.
            ContentBox(scheme: effectiveScheme) {
                if store.filteredTasks.isEmpty {
                    // System font, not Noto Serif — Brandon's request; this is
                    // a placeholder state, not real content.
                    Text(store.isLoading ? "Loading…" : "Nothing here yet.")
                        .font(.system(size: inputFontSize))
                        .foregroundStyle(Theme.secondaryText(effectiveScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    List(store.filteredTasks) { task in
                        TaskRowView(task: task, store: store)
                            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .cornerRadius(8)
                    .scrollContentBackground(.hidden)
                }
            }
            .padding(.top, 16)
        }
        // alignment: .top — otherwise frame(maxHeight: .infinity) centers this
        // VStack's now-short content (heading + one line of empty-state text)
        // within the tall imposed height, pushing content down with a gap
        // above it. Wasn't visible before because the empty state used to
        // have its own Spacers stretching the VStack to fill on its own.
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
