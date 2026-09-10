#if os(macOS)
import SwiftUI
import ArthurKit

/// 3 always-visible icon buttons (System/Light/Dark) — replaces the
/// segmented Picker that used to live in Settings, moved up to the main
/// pane's top-right per Brandon's "Maverick" reference. Each tap saves
/// immediately, same two-line pattern AgendaView's old pin-on-top button
/// used — no separate "Save"/"Done" step the way Settings' picker had.
struct AppearanceSwitcher: View {
    @ObservedObject var store: TaskStore
    let effectiveScheme: ColorScheme

    var body: some View {
        HStack(spacing: 4) {
            button(mode: .system, systemImage: "circle.lefthalf.filled")
            button(mode: .light, systemImage: "sun.max")
            button(mode: .dark, systemImage: "moon")
        }
    }

    private func button(mode: AppearanceMode, systemImage: String) -> some View {
        let isActive = store.config.appearance == mode
        return Button {
            store.config.appearance = mode
            store.config.save()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Theme.accentBright : Theme.secondaryText(effectiveScheme))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
