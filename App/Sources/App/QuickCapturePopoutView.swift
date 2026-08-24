#if os(macOS)
import SwiftUI
import ArthurKit

/// Mac-only "break out" window for Quick Capture's Craft box — a bigger,
/// independently movable/resizable surface for taking notes during a call,
/// modeled on Brandon's use of a separate app (Bits) for the same purpose.
/// Deliberately capture-only: no destination picker or Save button here —
/// Brandon's own scope cut ("I don't mind having to go back to the main
/// window to pick the destination"). Text lives in the shared
/// QuickCaptureDraft, not local state, so this window and the main Quick
/// Capture tab are always showing the exact same in-progress text — typing
/// here shows up there and vice versa, and closing this window via its red
/// traffic light (not just the return button below) never loses anything.
struct QuickCapturePopoutView: View {
    @EnvironmentObject var draft: QuickCaptureDraft
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var systemScheme

    // Defaults on, per Brandon's "the pop-out should default to always on
    // top, but I need to be able to unpin it." Own state, not tied to the
    // main window's mappin toggle in AgendaView — that one pins Arthur's
    // main window; this pins just this pop-out, independently.
    @State private var pinned = true

    private var effectiveScheme: ColorScheme {
        Theme.effectiveScheme(appearance: Config.load().appearance, system: systemScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button {
                    pinned.toggle()
                } label: {
                    Image(systemName: "mappin")
                        .font(.system(size: 16))
                        .foregroundStyle(pinned ? Theme.accentBright : Theme.secondaryText(effectiveScheme))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(pinned ? "Unpin from top" : "Pin on top")

                // There's nothing to actually "send back" — draft.text is
                // already shared live with the main window's Craft box.
                // This just closes the pop-out and brings the main window
                // forward so Brandon can pick a destination and Save there.
                Button {
                    dismissWindow(id: "quickCapturePopout")
                    openWindow(id: "main")
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.secondaryText(effectiveScheme))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Return to Arthur")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ZStack(alignment: .topLeading) {
                if draft.text.isEmpty {
                    Text("Capture a note…")
                        .font(.system(size: Theme.inputFontSize()))
                        .foregroundStyle(Theme.secondaryText(effectiveScheme))
                        .padding(16)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft.text)
                    .font(.system(size: Theme.inputFontSize()))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(12)
            }
        }
        .frame(minWidth: 360, minHeight: 240)
        .background(Theme.background(effectiveScheme))
        .foregroundStyle(Theme.primary(effectiveScheme))
        .pinnedOnTop(pinned)
        .restoresFrame(named: "quickCapturePopout")
    }
}
#endif
