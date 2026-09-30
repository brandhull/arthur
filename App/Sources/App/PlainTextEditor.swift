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
///
/// Also the fix for text visually disappearing mid-typing on iPad (Brandon:
/// several words into a Quick Capture, already-typed text would vanish —
/// cursor still visible/advancing, still able to type, but no glyphs) — see
/// the markedTextRange guard in UITextViewBridge.updateUIView for the root
/// cause and fix.
/// Shared by both platform bridges below — detects a "- "/"* " bullet marker
/// at the start of a line (any leading whitespace/tabs preserved as part of
/// the marker, so a nested/indented bullet's Return continues at the same
/// indent). Plain string logic, no platform text types, so both the AppKit
/// and UIKit bridges can call the same thing instead of drifting apart.
private func bulletMarker(in line: String) -> String? {
    let leading = line.prefix { $0 == " " || $0 == "\t" }
    let rest = line[leading.endIndex...]
    guard rest.hasPrefix("- ") || rest.hasPrefix("* ") else { return nil }
    return String(leading) + rest.prefix(2)
}

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
        Self.applyBulletIndent(view)
        return view
    }

    /// Word-processor-style bullet continuation: typing "- " (or "* ") and
    /// hitting Return keeps the marker going on the next line; hitting
    /// Return again on an now-empty bullet line exits bullet mode instead of
    /// stacking another dash — same two behaviors Notes/Word use. Paired
    /// with a hanging indent (applyBulletIndent below) so a wrapped bullet's
    /// second line lines up under its text, not back under the dash.
    /// Doesn't touch Craft's markdown: the literal "- " stays in the plain
    /// string that gets pushed, this is purely how it's laid out on screen
    /// while typing.
    static func applyBulletIndent(_ textView: UITextView) {
        let ns = textView.text as NSString
        let font = textView.font ?? .systemFont(ofSize: 15)
        let storage = textView.textStorage
        storage.beginEditing()
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { substring, _, enclosingRange, _ in
            let style = NSMutableParagraphStyle()
            if let marker = bulletMarker(in: substring ?? "") {
                let width = (marker as NSString).size(withAttributes: [.font: font]).width
                style.headIndent = width
            }
            storage.addAttribute(.paragraphStyle, value: style, range: enclosingRange)
        }
        storage.endEditing()
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Brandon: on iPad specifically, several words into typing in Quick
        // Capture, already-typed text would visually vanish — cursor still
        // visible and advancing, still able to keep typing, but the glyphs
        // themselves gone. Root cause: overwriting `.text` while iOS has an
        // active "marked text" session (the underlined candidate from
        // autocorrect/predictive typing) corrupts the text view's visual
        // layer without breaking the underlying input session — a
        // documented UIKit hazard, and far more likely on iPad because its
        // predictive-text bar suggests (and marks) far more aggressively
        // than iPhone's. `updateUIView` fires on effectively every SwiftUI
        // re-render, so `uiView.text = text` was firing mid-composition
        // constantly. Skipping the whole sync while marked text is pending
        // is the standard fix — the delegate callback below still keeps
        // `text` current once the candidate is committed/dismissed and
        // markedTextRange clears, so nothing is lost, just deferred.
        guard uiView.markedTextRange == nil else { return }
        if uiView.text != text { uiView.text = text }
        if uiView.font != font { uiView.font = font }
        if uiView.textColor != textColor { uiView.textColor = textColor }
        Self.applyBulletIndent(uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            UITextViewBridge.applyBulletIndent(textView)
        }

        /// Only intercepts an actual Return keypress (a lone "\n" insertion)
        /// — everything else (typing, paste, autocomplete) passes through
        /// unchanged. See PlainTextEditor's doc comment for why a manual
        /// NSTextStorage edit is used instead of letting UIKit insert the
        /// newline itself: it's the only way to also splice in the
        /// continued/removed bullet marker in the same edit.
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard replacement == "\n" else { return true }
            let ns = textView.text as NSString
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: range)
            let contentRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
            let lineText = ns.substring(with: contentRange)
            guard let marker = bulletMarker(in: lineText) else { return true }

            let afterMarker = lineText.dropFirst(marker.count)
            let storage = textView.textStorage
            if afterMarker.trimmingCharacters(in: .whitespaces).isEmpty {
                // Empty bullet ("- " with nothing typed after it yet) —
                // Return exits bullet mode by clearing the marker instead of
                // starting a new bulleted line.
                storage.replaceCharacters(in: contentRange, with: "")
                textView.selectedRange = NSRange(location: contentRange.location, length: 0)
            } else {
                let insertion = "\n" + marker
                storage.replaceCharacters(in: range, with: insertion)
                textView.selectedRange = NSRange(location: range.location + (insertion as NSString).length, length: 0)
            }
            text.wrappedValue = textView.text
            UITextViewBridge.applyBulletIndent(textView)
            return false
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
        Self.applyBulletIndent(textView)

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

    /// Same behavior/reasoning as UITextViewBridge's version of this — see
    /// its doc comment. NSParagraphStyle/.paragraphStyle is the same
    /// Foundation type/key on both platforms, just measured against an
    /// NSFont here instead of a UIFont.
    static func applyBulletIndent(_ textView: NSTextView) {
        let ns = textView.string as NSString
        let font = textView.font ?? .systemFont(ofSize: 15)
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { substring, _, enclosingRange, _ in
            let style = NSMutableParagraphStyle()
            if let marker = bulletMarker(in: substring ?? "") {
                let width = (marker as NSString).size(withAttributes: [.font: font]).width
                style.headIndent = width
            }
            storage.addAttribute(.paragraphStyle, value: style, range: enclosingRange)
        }
        storage.endEditing()
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        // Same class of bug as UITextViewBridge's identical guard (see its
        // comment) — overwriting .string while AppKit has an active marked-
        // text session (IME composition, e.g. CJK input) is the AppKit
        // equivalent hazard. Less likely to trigger via plain autocorrect
        // on Mac, but cheap to guard against for the same reason.
        guard !textView.hasMarkedText() else { return }
        if textView.string != text { textView.string = text }
        if textView.font != font { textView.font = font }
        if textView.textColor != textColor { textView.textColor = textColor }
        Self.applyBulletIndent(textView)
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
            NSTextViewBridge.applyBulletIndent(textView)
        }

        /// Same bullet-continue/exit behavior as UITextViewBridge's
        /// shouldChangeTextIn — see its doc comment. AppKit's equivalent
        /// interception point is doCommandBy:, firing for the Return key's
        /// insertNewline: selector specifically (not every text change, so
        /// no replacement-text filter needed the way iOS's delegate call
        /// does).
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let ns = textView.string as NSString
            let selRange = textView.selectedRange()
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: selRange)
            let contentRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
            let lineText = ns.substring(with: contentRange)
            guard let marker = bulletMarker(in: lineText) else { return false }

            let afterMarker = lineText.dropFirst(marker.count)
            if afterMarker.trimmingCharacters(in: .whitespaces).isEmpty {
                textView.insertText("", replacementRange: contentRange)
            } else {
                textView.insertText("\n" + marker, replacementRange: selRange)
            }
            text.wrappedValue = textView.string
            NSTextViewBridge.applyBulletIndent(textView)
            return true
        }
    }
}
#endif
