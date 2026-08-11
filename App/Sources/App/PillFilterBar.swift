import SwiftUI

/// Custom capsule-pill filter row — not the native segmented Picker, which
/// is themed by the system accent color with no supported way to override
/// just the selected segment's fill/text color (Brandon explicitly didn't
/// want that blue). Used by Tasks' Today/Tomorrow filter and Quick
/// Capture's Craft/Baserow source toggle — pulled out into one shared
/// component specifically because Brandon asked for the Quick Capture
/// toggle to visually duplicate the Tasks filter exactly; sharing the
/// actual view code guarantees that instead of two copies drifting apart.
struct PillFilterBar<Item: Identifiable & Hashable>: View {
    let items: [Item]
    let label: (Item) -> String
    @Binding var selection: Item
    let scheme: ColorScheme
    var fontSize: CGFloat = 13

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let isSelected = selection == item
                Button {
                    selection = item
                } label: {
                    Text(label(item))
                        .font(.system(size: fontSize, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 14)
                        // Mac: fixed to Theme.controlHeight instead of
                        // vertical padding — Brandon: once the tab bar
                        // became a dropdown, these pills read as noticeably
                        // shorter next to it ("tiny"). A shared explicit
                        // height, the same one the dropdown itself uses,
                        // guarantees they match instead of drifting again
                        // the next time either one's padding changes.
                        //
                        // iOS/iPadOS keep the padding-based sizing and the
                        // full-width stretch — not flagged as a problem
                        // there, and a two-item pill bar reads better
                        // filling a phone-width row.
                        #if os(macOS)
                        .frame(height: Theme.controlHeight())
                        #else
                        .padding(.vertical, verticalPadding)
                        .frame(maxWidth: .infinity)
                        #endif
                        .background(
                            Capsule().fill(isSelected ? Theme.selectedFilterBackground(scheme) : Color.clear)
                        )
                        .foregroundStyle(isSelected ? Theme.selectedFilterForeground(scheme) : Theme.primary(scheme))
                        // Without this, .buttonStyle(.plain) only registers
                        // taps on the Text glyphs themselves — the
                        // .frame(maxWidth: .infinity) above expands the
                        // *layout* size but not the tappable hit area, so
                        // most of each pill (everything past the label text)
                        // was dead space. Explicit contentShape makes the
                        // whole capsule tappable, matching what it looks like.
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        // No outer padding before the track fill — that used to outset the
        // track 3pt beyond the pills on every side, which meant the whole
        // bar's leading edge sat 3pt right of where PillActionButton's
        // (Edit/Save/Cancel) flush capsule starts, and 3pt inside the
        // shared 20pt row margin that the tab dropdown/ContentBox align to.
        // Brandon caught both as the same drift: on Mac, paging between
        // tabs showed the button's left edge visibly shift; on iOS/iPadOS,
        // the pill bar didn't reach the same margins as the dropdown above
        // and the container below. Flush now matches all three exactly.
        .background(Capsule().fill(Theme.primary(scheme).opacity(0.08)))
    }

    /// Platform-specific, not a shared constant — pixel-measured against
    /// PillButton's actual rendered height on each platform (Mac's system
    /// font renders this text taller per point than iOS's at the same
    /// size, so one padding value doesn't produce a matching height on
    /// both).
    private var verticalPadding: CGFloat {
        #if os(macOS)
        return 5
        #else
        return 10
        #endif
    }
}

/// A single capsule button styled identically to one *selected* pill inside
/// PillFilterBar (same font size, padding, capsule shape, and fill/text
/// colors) — used for Rocks/Reflection's "Edit"/"Save"/"Cancel" buttons so
/// they read as the exact same kind of control as the Tasks filter and
/// Quick Capture's Craft/Baserow toggle, at the same position in the header
/// row (leading edge, not trailing — Brandon wanted all four tabs' header
/// rows to place their one interactive element in the identical spot).
/// Deliberately duplicates PillFilterBar's font/padding constants rather
/// than sharing them — those are private to keep PillFilterBar's own
/// surface area small, and this is simple enough not to be worth threading
/// them through as parameters.
struct PillActionButton: View {
    let label: String
    let scheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: fontSize, weight: .medium))
                .padding(.horizontal, 14)
                #if os(macOS)
                .frame(height: Theme.controlHeight())
                #else
                .padding(.vertical, verticalPadding)
                #endif
                .background(Capsule().fill(Theme.selectedFilterBackground(scheme)))
                .foregroundStyle(Theme.selectedFilterForeground(scheme))
        }
        .buttonStyle(.plain)
    }

    private var fontSize: CGFloat {
        #if os(macOS)
        return 14
        #else
        return 13
        #endif
    }

    private var verticalPadding: CGFloat {
        #if os(macOS)
        return 5
        #else
        return 10
        #endif
    }
}
