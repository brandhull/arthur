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
/// Owns its own content padding (12pt, matching the placeholder Text every
/// call site already uses) so callers no longer need the old asymmetric
/// "leading 7 instead of 12" compensation hack scattered across the app —
/// that offset (for TextEditor's own built-in lineFragmentPadding) now
/// lives once, inside this component, on the macOS branch only.
struct PlainTextEditor: View {
    @Binding var text: String
    let fontSize: CGFloat
    let scheme: ColorScheme

    var body: some View {
        #if os(iOS)
        UITextViewBridge(text: $text, font: .systemFont(ofSize: fontSize), textColor: UIColor(Theme.primary(scheme)))
            .padding(12)
        #else
        TextEditor(text: $text)
            .font(.system(size: fontSize))
            .scrollContentBackground(.hidden)
            .background(Color.clear) // macOS TextEditor keeps its own NSTextView background even with scrollContentBackground(.hidden) — forces it transparent so the surrounding FieldBox/ContentBox fill shows through instead of a generic system gray.
            .padding(.top, 12)
            .padding(.bottom, 12)
            .padding(.trailing, 12)
            .padding(.leading, 7) // TextEditor bakes in a ~5pt lineFragmentPadding a plain Text has no equivalent of; this keeps the cursor/typed text flush with the placeholder's own leading edge.
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
