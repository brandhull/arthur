import SwiftUI

/// Drop-in replacement for every plain-text `TextEditor` in the app
/// (Quick Capture's Craft box, Rocks/Reflection's edit mode, Add Note,
/// Search Baserow, and Baserow's long_text field — not the Mac-only Quick
/// Capture pop-out, which stays on native TextEditor since it never runs
/// on iOS).
///
/// Works around a well-documented SwiftUI/UIKit bug, confirmed live on
/// iPhone and iPad (Brandon's screenshots): an *empty* `TextEditor` on iOS
/// renders its caret sized to UITextView's own default line-height instead
/// of whatever `.font()` size was requested, until the very first
/// keystroke — visually a too-tall, misaligned cursor next to a correctly-
/// sized placeholder. Not present on macOS (confirmed working there) —
/// NSTextView-backed TextEditor doesn't have this bug, only UIKit's
/// UITextView-backed one does.
///
/// A first attempt fixed this via `UITextView.appearance().font` at app
/// launch — the standard lower-risk workaround — but Brandon confirmed
/// live it did NOT fix the actual bug (screenshots), so that's abandoned
/// here in favor of the real fix: a small UIViewRepresentable wrapping
/// UITextView directly, which sets the font imperatively at creation
/// instead of relying on SwiftUI's `.font()` modifier/UIAppearance timing,
/// which is what actually avoids the bug.
///
/// Also the fix for spellcheck not appearing (Brandon: Mac, specifically
/// while typing in Quick Capture — "90% of what I use Arthur for"). SwiftUI's
/// native TextEditor exposes no modifier for NSTextView's
/// isContinuousSpellCheckingEnabled, and it isn't on by default for a
/// programmatically-created NSTextView (unlike one built in a nib/storyboard,
/// where Interface Builder's own default checks that box) — so macOS's
/// native TextEditor silently never spellchecked here at all. Wrapping
/// NSTextView directly, the same way UITextView already is for iOS, is what
/// lets that be turned on explicitly.
///
/// Owns its own content padding (12pt, matching the placeholder Text every
/// call site already uses) so callers no longer need the old asymmetric
/// "leading 7 instead of 12" compensation hack scattered across the app —
/// that offset (for TextEditor's own built-in lineFragmentPadding) is
/// zeroed out directly in both platforms' wrapped text views instead.
struct PlainTextEditor: View {
    @Binding var text: String
    let fontSize: CGFloat
    let scheme: ColorScheme
    /// Mac-only, opt-in: when this flips from false to true, the field
    /// grabs first responder automatically — used by Quick Capture's Craft
    /// box so switching into it from the sidebar drops the cursor there
    /// immediately, no click needed. Ignored on iOS (not asked for there).
    /// Not a @Binding — this is a one-way trigger, not state PlainTextEditor
    /// itself needs to report back.
    var autoFocusWhen: Bool = false

    var body: some View {
        #if os(iOS)
        UITextViewBridge(text: $text, font: .systemFont(ofSize: fontSize), textColor: UIColor(Theme.primary(scheme)))
            .padding(12)
        #else
        NSTextViewBridge(
            text: $text, font: .systemFont(ofSize: fontSize), textColor: NSColor(Theme.primary(scheme)),
            autoFocusWhen: autoFocusWhen
        )
        .padding(12)
        #endif
    }
}

#if os(iOS)
import UIKit

private struct UITextViewBridge: UIViewRepresentable {
    @Binding var text: String
    let font: UIFont
    let textColor: UIColor

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = font
        view.textColor = textColor
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = true
        view.isEditable = true
        view.isUserInteractionEnabled = true
        // Explicit rather than relying on UITextView's own default — .default
        // lets the system infer behavior from context, which wasn't reliably
        // showing squiggly underlines in testing; .yes forces it on
        // unconditionally, the same certainty macOS's isContinuousSpell-
        // CheckingEnabled = true gives on the other platform.
        view.spellCheckingType = .yes
        view.autocorrectionType = .default
        view.delegate = context.coordinator
        view.text = text
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
        if uiView.font != font { uiView.font = font }
        if uiView.textColor != textColor { uiView.textColor = textColor }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
    }
}
#endif

#if os(macOS)
import AppKit

private struct NSTextViewBridge: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let textColor: NSColor
    var autoFocusWhen: Bool = false

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.font = font
        textView.textColor = textColor
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        // The actual fix — see PlainTextEditor's own doc comment for why
        // this was never on in the first place (native TextEditor gave no
        // way to set it, and NSTextView doesn't default to true when
        // created programmatically instead of via a nib).
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.delegate = context.coordinator
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        // Without this, the scroller track/thumb stayed visibly drawn in
        // the corner even when there was nothing to scroll (an empty or
        // short capture box) — autohidesScrollers is what tells AppKit to
        // only actually show it while scrolling/content overflows, rather
        // than keeping it permanently present just because
        // hasVerticalScroller made one exist.
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text }
        if textView.font != font { textView.font = font }
        if textView.textColor != textColor { textView.textColor = textColor }
        // Edge-triggered, not "focus whenever true" — this view is never
        // destroyed/recreated across an outer tab switch (the opacity-swap
        // pattern), so without tracking the previous value, an already-true
        // autoFocusWhen would try to steal focus back on every unrelated
        // SwiftUI update, fighting the user if they'd clicked elsewhere.
        if autoFocusWhen, !context.coordinator.wasAutoFocusRequested {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
        context.coordinator.wasAutoFocusRequested = autoFocusWhen
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var wasAutoFocusRequested = false
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
#endif
