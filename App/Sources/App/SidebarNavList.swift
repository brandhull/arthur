import SwiftUI
import ArthurKit

/// The nav list (Rocks, Bits, Tasks, "Quick Capture" label + nested Craft/
/// Baserow rows, Reflection) plus the bottom-pinned Settings
/// gear row —
/// extracted out of Mac's SidebarView so the exact same nav content can be
/// reused by the iOS drawer (iPhone/iPad portrait) and the iPad landscape
/// persistent sidebar, without three copies of this logic drifting apart.
/// Platform-neutral: no `#if os(macOS)` guard, since none of this is
/// Mac-specific — only each consumer's own top-row chrome (collapse toggle,
/// quick-add button) around it differs, which is why that row isn't part
/// of this view at all.
struct SidebarNavList: View {
    @Binding var selectedTab: HomeTab
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
                navRow(title: HomeTab.quickCapture.rawValue, isActive: selectedTab == .quickCapture) {
                    selectedTab = .quickCapture
                }
                navRow(title: HomeTab.rocks.rawValue, isActive: selectedTab == .rocks) {
                    selectedTab = .rocks
                }
                navRow(title: HomeTab.bits.rawValue, isActive: selectedTab == .bits) {
                    selectedTab = .bits
                }
                navRow(title: HomeTab.tasks.rawValue, isActive: selectedTab == .tasks) {
                    selectedTab = .tasks
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
                .frame(height: navRowHeight)
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
