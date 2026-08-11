import SwiftUI

/// A native Menu styled to match FieldBox/ContentBox's own hairline-outline
/// treatment rather than looking like a system control — originally the top
/// nav's tab selector (AgendaView.tabDropdown), pulled out into a shared
/// component so Search Baserow's Database/Table selectors can be its exact
/// visual sibling ("same dimensions as the navigation dropdown," per
/// Brandon's request) instead of a hand-copied second version that could
/// drift from it later.
struct DropdownButton<Item: Identifiable & Hashable>: View {
    let items: [Item]
    let label: (Item) -> String
    @Binding var selection: Item?
    var placeholder: String
    let scheme: ColorScheme
    let font: Font
    let height: CGFloat
    var disabled: Bool = false

    var body: some View {
        Menu {
            ForEach(items) { item in
                Button(label(item)) { selection = item }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selection.map(label) ?? placeholder)
                    .font(font)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText(scheme))
            }
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.primary(scheme).opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.primary(scheme).opacity(Theme.borderOpacity), lineWidth: Theme.borderWidth)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.primary(scheme))
        .disabled(disabled)
    }
}
