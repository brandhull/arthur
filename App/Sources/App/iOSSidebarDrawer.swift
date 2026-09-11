#if os(iOS)
import SwiftUI
import ArthurKit

/// The iPhone / iPad-portrait hamburger drawer — a dimming scrim (tap to
/// dismiss) plus a panel sliding in from the leading edge at ~75% of the
/// screen's width, containing just SidebarNavList (the same 6 nav rows +
/// Settings gear Mac's sidebar shows). Flush/edge-to-edge styling, not
/// Mac's floating-card treatment — Brandon only asked for that look on
/// iPad's landscape persistent sidebar (see iPadLandscapeSidebar), not
/// here. No top row of its own (no collapse toggle, no quick-add button) —
/// those live in the main top bar instead, per Brandon's literal
/// description of this drawer's contents.
struct iOSSidebarDrawer: View {
    @Binding var selectedTab: HomeTab
    @Binding var quickCaptureSource: QuickCaptureSource
    @Binding var showingSettings: Bool
    @Binding var isPresented: Bool
    let width: CGFloat
    let effectiveScheme: ColorScheme

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            // The background alone ignores the safe area (so the drawer's
            // fill extends full-bleed behind the status bar/home
            // indicator) — the nav content itself does NOT, and gets
            // generous padding on top of that safe area on every edge:
            // top (Brandon: "Rocks" rendered right up against the status
            // bar with just 8pt), bottom (Settings sat right at the home
            // indicator), and leading (rows started flush with the
            // drawer's own edge). Extra padding lives here, not inside
            // SidebarNavList itself, since Mac's sidebar and the iPad
            // landscape sidebar already have correct spacing from their
            // own chrome and shouldn't also pick this up.
            SidebarNavList(
                selectedTab: $selectedTab, quickCaptureSource: $quickCaptureSource,
                showingSettings: $showingSettings, effectiveScheme: effectiveScheme
            )
            .padding(.top, 60)
            .padding(.bottom, 24)
            .padding(.leading, 12)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background(
                Theme.background(effectiveScheme)
                    .ignoresSafeArea(edges: .vertical)
            )
        }
        // Tapping any destination or opening Settings closes the drawer —
        // standard drawer UX. Handled here (not inside SidebarNavList
        // itself) so that shared component stays free of any drawer-
        // specific behavior; Mac's sidebar and the iPad landscape sidebar
        // don't need this at all since they're always visible.
        .onChange(of: selectedTab) { isPresented = false }
        .onChange(of: quickCaptureSource) { isPresented = false }
        .onChange(of: showingSettings) {
            if showingSettings { isPresented = false }
        }
    }
}
#endif
