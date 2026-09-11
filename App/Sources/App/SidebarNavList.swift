import SwiftUI
import ArthurKit

/// The 6-row nav list (Rocks, Tasks, "Quick Capture" label + nested Craft/
/// Baserow rows, Reflection) plus the bottom-pinned Settings gear row —
/// extracted out of Mac's SidebarView so the exact same nav content can be
/// reused by the iOS drawer (iPhone/iPad portrait) and the iPad landscape
/// persistent sidebar, without three copies of this logic drifting apart.
/// Platform-neutral: no `#if os(macOS)` guard, since none of this is
/// Mac-specific — only each consumer's own top-row chrome (collapse toggle,
/// quick-add button) around it differs, which is why that row isn't part
/// of this view at all.
struct SidebarNavList: View {
    @Binding var selectedTab: HomeTab
    @Binding var quickCaptureSource: QuickCaptureSource
    @Binding var showingSettings: Bool
    let effectiveScheme: ColorScheme

    // Mac keeps its original 14pt/30pt-row sizing (unaffected by Brandon's
    // iOS standardization ask); iOS/iPadOS now match Theme.inputFontSize
    // (= the header date's own size) — the row height grows along with it
    // so 20pt text isn't cramped in what was tuned for 14pt.
    private var navFontSize: CGFloat {
        #if os(macOS)
        return 14
        #else
        return Theme.inputFontSize()
        #endif
    }
    private var navRowHeight: CGFloat {
        #if os(macOS)
        return 30
        #else
        return 40
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                // itself doesn't need to be tappable. Same font/size/color as
                // every other nav row (Brandon: all sidebar text should read
                // as one uniform style, not a visually distinct section
                // header) — only the missing dot and disabled tap tell it
                // apart from an active/inactive leaf row. Same fixed 30pt
                // row height too, not its own top/bottom padding — that
                // used to make the gap above it (from Tasks) read as 12pt
                // while the gap below it (to Craft) read as only 4pt, so
                // Craft looked oddly "closer" to the label than every other
                // row is to its neighbor. Every row-to-row gap is now
                // exactly the same, set purely by this VStack's own
                // `spacing: 2`.
                Text(HomeTab.quickCapture.rawValue)
                    .font(.system(size: navFontSize, weight: .regular))
                    .foregroundStyle(Theme.primary(effectiveScheme))
                    .padding(.horizontal, 14)
                    .frame(height: navRowHeight)
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
                        .font(.system(size: navFontSize))
                    Text("Settings")
                        .font(.system(size: navFontSize, weight: .regular))
                    Spacer()
                }
                .foregroundStyle(Theme.primary(effectiveScheme))
                .padding(.horizontal, 14)
                .frame(height: navRowHeight + 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Theme.primary(effectiveScheme))
    }

    private func navRow(title: String, isActive: Bool, indent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Default (primary) color, regular weight for every row —
                // selection is conveyed by the dot alone, not a font-weight
                // change, per Brandon's exact spec.
                Text(title)
                    .font(.system(size: navFontSize, weight: .regular))
                    .foregroundStyle(Theme.primary(effectiveScheme))
                Spacer()
                if isActive {
                    Circle()
                        .fill(Theme.accentBright)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.leading, indent ? 26 : 14)
            .padding(.trailing, 14)
            .frame(height: navRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
