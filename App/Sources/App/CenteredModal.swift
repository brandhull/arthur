import SwiftUI
import ArthurKit

/// Single shared presentation for the bubble.and.pencil quick-add popup —
/// used identically by Mac's sidebar, iPad's landscape sidebar and portrait
/// top bar, and iPhone's floating button. Those four call sites used to each
/// present QuickAddModal via their own `.popover`, which put it in four
/// different screen positions (anchored below Mac's sidebar button, anchored
/// below iPad's, auto-converted into a bottom sheet on iPhone) with
/// different fonts between platforms — Brandon's ask was for one consistent
/// modal, dead-center of the app window, on every platform, with an explicit
/// close button rather than relying on each platform's own dismiss gesture.
///
/// Mounted once at AgendaView's own top level (an `.overlay` on the whole
/// window-filling Group, not on any individual button) so it centers over
/// the *entire* app window/screen — every call site now just flips the same
/// shared `showingQuickAdd` binding to true instead of attaching its own
/// popover.
struct CenteredModal<Content: View>: View {
    @Binding var isPresented: Bool
    let effectiveScheme: ColorScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isPresented {
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { isPresented = false }

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button {
                            isPresented = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.secondaryText(effectiveScheme))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 6)
                    .padding(.trailing, 6)

                    content()
                }
                .background(
                    RoundedRectangle(cornerRadius: Theme.sidebarCardCornerRadius, style: .continuous)
                        .fill(Theme.sidebarCardBackground(effectiveScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.sidebarCardCornerRadius, style: .continuous)
                        .stroke(Theme.primary(effectiveScheme).opacity(Theme.borderOpacity), lineWidth: Theme.borderWidth)
                )
                // One fixed width for both of QuickAddModal's modes (menu
                // and the inline New Reflection compose box) — part of
                // making this read as one consistent modal rather than
                // resizing itself between two different widths depending on
                // what's showing.
                .frame(width: 300)
                .shadow(color: Color.black.opacity(0.25), radius: 24, y: 10)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .animation(.easeOut(duration: 0.15), value: isPresented)
        }
    }
}
