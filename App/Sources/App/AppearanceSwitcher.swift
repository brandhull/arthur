#if os(macOS)
import SwiftUI
import ArthurKit

/// 3 always-visible icon buttons (System/Light/Dark) — replaces the
/// segmented Picker that used to live in Settings, moved up to the main
/// pane's top-right per Brandon's "Maverick" reference. Each tap applies
/// immediately — no separate "Save"/"Done" step the way Settings' picker
/// had. Not followed by store.config.save(): Config.appearance is a local-
/// only computed property (writes straight to this device's UserDefaults,
/// see Config's own comment) precisely so toggling it here doesn't also
/// re-push the rest of Config to other devices over iCloud — Brandon
/// flagged that flipping appearance on Mac was live-changing iPad's too,
/// back when appearance was one field inside the synced blob.
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
