import SwiftUI
import AppKit

/// Drop-in replacement for `TextEditor` in ArthurBar's Quick Capture panel.
/// SwiftUI's `.scrollIndicators(.hidden)` modifier has no effect on
/// TextEditor's underlying NSScrollView on macOS — the scroller track/thumb
/// stayed visibly drawn even on an empty box, tied to the system's own
/// "Show scroll bars: Always" setting (Brandon's case: "get rid of the
/// ghost scroll bar... only make it appear when needed"). Wrapping
/// NSTextView directly and setting `autohidesScrollers = true` is the real
/// fix — the main app's PlainTextEditor solves this identical problem the
/// same way for its own Craft capture box.
struct BarTextEditor: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.font = font
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.delegate = context.coordinator
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        // `autohidesScrollers` alone wasn't enough with the system's "Show
        // scroll bars: Always" preference (Brandon's case) — that setting
        // pins every NSScroller to the legacy (always-drawn) style, and
        // legacy-style scrollers stay visible regardless of
        // autohidesScrollers. Forcing .overlay here overrides that
        // preference for just this scroll view, which is what actually
        // makes the thumb transient (appears while scrolling, fades out
        // otherwise) instead of a permanent fixture.
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // NSScrollView can silently reset scrollerStyle back to the
        // system's preference (legacy, in Brandon's case) once it's
        // actually attached to a window — re-asserting it on every update
        // (cheap/idempotent) is what makes the override actually stick.
        nsView.scrollerStyle = .overlay
        guard let textView = nsView.documentView as? NSTextView else { return }
        // Same marked-text hazard the main app's PlainTextEditor guards
        // against — overwriting .string mid-IME-composition (e.g. CJK
        // input) corrupts the text view's visual layer.
        guard !textView.hasMarkedText() else { return }
        if textView.string != text { textView.string = text }
        if textView.font != font { textView.font = font }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
