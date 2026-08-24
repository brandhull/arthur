#if os(macOS)
import SwiftUI
import ArthurKit
import AppKit

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
                //
                // NOT openWindow(id: "main") — that's the bug Brandon hit:
                // openWindow(id:) on a WindowGroup always spawns a *new*
                // window instance rather than refocusing the existing one
                // (that "bring existing one forward" behavior only applies
                // to the singular Window scene type, which is what the
                // pop-out itself uses). Calling it here created a second
                // full Arthur window, complete with its own fresh splash
                // screen replay, every time "return" was tapped. Finding
                // and refocusing the real window via AppKit sidesteps that
                // entirely — no new window is ever created.
                Button {
                    dismissWindow(id: "quickCapturePopout")
                    NSApp.windows.first(where: { $0.title == "Arthur" })?.makeKeyAndOrderFront(nil)
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
                        .padding(12)
                        .allowsHitTesting(false)
                }
                // Same padding pattern as QuickCaptureView's Craft box and
                // SearchBaserowView's search box — 12 on every edge except
                // leading, which drops to 7 to compensate for TextEditor's
                // own ~5pt internal inset that the placeholder Text doesn't
                // have. This pop-out originally used mismatched values (16
                // for the placeholder, a flat 12/no-compensation for the
                // TextEditor) with no leading offset at all, which is what
                // put the cursor visibly out of position/size relative to
                // the placeholder — not a font-size bug, a padding bug.
                TextEditor(text: $draft.text)
                    .font(.system(size: Theme.inputFontSize()))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .padding(.trailing, 12)
                    .padding(.leading, 7)
            }
        }
        .frame(minWidth: 360, minHeight: 240)
        .background(Theme.background(effectiveScheme))
        .foregroundStyle(Theme.primary(effectiveScheme))
        // Without this, the pop-out's actual AppKit window appearance never
        // gets told to go dark — it was left following the OS default,
        // independent of Config.appearance/effectiveScheme. That's harmless
        // for colors defined as plain RGB (Theme.background/primary), but
        // Theme.secondaryText resolves to the *dynamic* system color
        // NSColor.secondaryLabelColor, which reads the window's real
        // appearance, not this computed effectiveScheme — so the unpinned
        // mappin (secondaryText) rendered as light-mode's dark gray against
        // this manually-forced-dark background and was nearly invisible.
        // Every other window in the app gets this from AgendaView/the
        // various sheets; the pop-out just never had it.
        .preferredColorScheme(effectiveScheme)
        .pinnedOnTop(pinned)
        .restoresFrame(named: "quickCapturePopout")
    }
}
#endif
