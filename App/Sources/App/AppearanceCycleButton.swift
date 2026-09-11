#if os(iOS)
import SwiftUI
import ArthurKit

/// iOS's rolled-up appearance control — Mac gets 3 direct-select icons
/// (AppearanceSwitcher), but Brandon wants iPhone/iPad's top bar to carry
/// just one icon instead. Fixed `sun.max` glyph regardless of the current
/// mode (per Brandon's exact description — no state-dependent styling);
/// tapping cycles System → Light → Dark → System via AppearanceMode's own
/// CaseIterable ordering.
struct AppearanceCycleButton: View {
    @ObservedObject var store: TaskStore
    let effectiveScheme: ColorScheme

    var body: some View {
        Button {
            let all = AppearanceMode.allCases
            let current = store.config.appearance
            let currentIndex = all.firstIndex(of: current) ?? 0
            store.config.appearance = all[(currentIndex + 1) % all.count]
        } label: {
            Image(systemName: "sun.max")
                .font(.system(size: 18))
                .foregroundStyle(Theme.primary(effectiveScheme))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
