import SwiftUI

/// Rounded-corner box button used for "Add Task" and "Add to Note" — replaces
/// the earlier free-floating "+" icon per Brandon's request.
struct PillButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(label)
            }
            // Mac keeps the scalable .subheadline token; iOS/iPadOS now
            // match Theme.inputFontSize (= the header date's own size), per
            // Brandon's ask to collapse every scattered iOS text size to
            // one standard — this button (Save/Push/Add) is exactly the
            // kind of "text I type and act on" it was meant to cover.
            #if os(macOS)
            .font(.subheadline.weight(.semibold))
            #else
            .font(.system(size: Theme.inputFontSize(), weight: .semibold))
            #endif
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.primary(scheme))
            )
            .foregroundStyle(scheme == .dark ? Color.black : Color.white)
        }
        .buttonStyle(.plain)
    }
}
