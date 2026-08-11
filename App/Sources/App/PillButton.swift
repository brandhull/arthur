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
            .font(.subheadline.weight(.semibold))
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
