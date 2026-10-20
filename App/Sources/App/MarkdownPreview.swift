import SwiftUI
import ArthurKit

/// Draws typed text the way Craft will receive it (blocks come from
/// `CraftMarkdown.parse`, which follows Craft's real import rules). Used by
/// the capture screens' preview toggle. Not a pixel match for Craft — callouts,
/// tables and Craft's own theming aren't reproduced — but block structure,
/// line breaks, lists, checkboxes, dividers and inline formatting are.
///
/// Separate from MarkdownContentView, which renders Craft's *export* for
/// Rocks and Reflection (one line = one block); this follows the *import*
/// rules, where consecutive lines share a block.
struct MarkdownPreview: View {
    let text: String
    /// When set (New Document), drawn first as the page's title.
    var title: String?
    let fontSize: CGFloat
    let scheme: ColorScheme

    var body: some View {
        let blocks = CraftMarkdown.parse(text)
        let numbers = CraftMarkdown.numbering(for: blocks)
        VStack(alignment: .leading, spacing: 0) {
            if let title, !title.isEmpty {
                Text(inline(title))
                    .font(.system(size: fontSize + 12, weight: .bold))
                    .foregroundStyle(Theme.primary(scheme))
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                row(block, number: numbers[index])
                    .padding(.top, spacing(before: index, in: blocks))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Layout

    private func isListItem(_ block: CraftMarkdown.Block) -> Bool {
        switch block {
        case .bullet, .numbered, .task, .toggle: return true
        default: return false
        }
    }

    /// List items sit close together; other blocks get a full line of air.
    private func spacing(before index: Int, in blocks: [CraftMarkdown.Block]) -> CGFloat {
        if index == 0 { return (title?.isEmpty == false) ? 14 : 0 }
        if isListItem(blocks[index]) && isListItem(blocks[index - 1]) { return 4 }
        if case .heading = blocks[index], index > 0 { return 18 }
        return 10
    }

    // MARK: - Blocks

    @ViewBuilder
    private func row(_ block: CraftMarkdown.Block, number: Int?) -> some View {
        switch block {
        case .paragraph(let text):
            Text(inline(text)).font(bodyFont).lineSpacing(4)
                .foregroundStyle(Theme.primary(scheme))

        case .heading(let level, let text):
            Text(inline(text))
                .font(.system(size: headingSize(level), weight: .semibold))
                .foregroundStyle(Theme.primary(scheme))

        case .bullet(let level, let text):
            marked("•", level: level, text: text)

        case .numbered(let level, let text):
            marked("\(number ?? 1).", level: level, text: text)

        case .toggle(let level, let text):
            marked("▸", level: level, text: text)

        case .task(let level, let done, let text):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: done ? "checkmark.square.fill" : "square")
                    .font(bodyFont)
                    .foregroundStyle(done ? Theme.accentBright : Theme.secondaryText(scheme))
                Text(inline(text)).font(bodyFont).lineSpacing(4)
                    .strikethrough(done)
                    .foregroundStyle(done ? Theme.secondaryText(scheme) : Theme.primary(scheme))
            }
            .padding(.leading, indent(level))

        case .quote(let text):
            Text(inline(text)).font(bodyFont).italic().lineSpacing(4)
                .foregroundStyle(Theme.secondaryText(scheme))
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Theme.primary(scheme).opacity(0.3)).frame(width: 2)
                }

        case .divider:
            Rectangle()
                .fill(Theme.primary(scheme).opacity(0.25))
                .frame(height: 1)
                .padding(.vertical, 6)

        case .code(let code):
            Text(code)
                .font(.system(size: fontSize - 1, design: .monospaced))
                .foregroundStyle(Theme.primary(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.primary(scheme).opacity(0.06))
                )
        }
    }

    private func marked(_ marker: String, level: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(marker).font(bodyFont).foregroundStyle(Theme.primary(scheme))
            Text(inline(text)).font(bodyFont).lineSpacing(4)
                .foregroundStyle(Theme.primary(scheme))
        }
        .padding(.leading, indent(level))
    }

    private var bodyFont: Font { .system(size: fontSize) }

    private func indent(_ level: Int) -> CGFloat { CGFloat(level) * 22 }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return fontSize + 10
        case 2: return fontSize + 6
        case 3: return fontSize + 3
        default: return fontSize + 1
        }
    }

    // MARK: - Inline formatting

    /// Bold, italic, code, links and strikethrough via Foundation's markdown
    /// parser (whitespace/line breaks preserved), plus Craft's `==highlight==`.
    /// Craft writes strikethrough with a single `~`, which Foundation doesn't
    /// read, so it's widened to `~~` first.
    private func inline(_ source: String) -> AttributedString {
        var result = AttributedString()
        for piece in Self.splitHighlights(source) {
            var attributed = Self.parseInline(piece.text)
            if piece.highlighted { attributed.backgroundColor = Color.yellow.opacity(0.45) }
            result += attributed
        }
        return result
    }

    private static func parseInline(_ source: String) -> AttributedString {
        let converted = source.replacingOccurrences(
            of: #"(?<!~)~(?!~)([^~\n]+)~(?!~)"#, with: "~~$1~~", options: .regularExpression)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: converted, options: options)) ?? AttributedString(source)
    }

    private static func splitHighlights(_ source: String) -> [(text: String, highlighted: Bool)] {
        guard let regex = try? NSRegularExpression(pattern: #"==([^=\n]+)=="#) else { return [(source, false)] }
        let ns = source as NSString
        var pieces: [(String, Bool)] = []
        var cursor = 0
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            if match.range.location > cursor {
                pieces.append((ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), false))
            }
            pieces.append((ns.substring(with: match.range(at: 1)), true))
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length { pieces.append((ns.substring(from: cursor), false)) }
        return pieces.isEmpty ? [(source, false)] : pieces
    }
}

/// The scrolling preview surface a capture screen shows in place of its
/// editor while previewing, with an empty-state message.
struct CapturePreviewPane: View {
    let text: String
    var title: String?
    let fontSize: CGFloat
    let scheme: ColorScheme

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (title ?? "").isEmpty
    }

    var body: some View {
        ScrollView {
            if isEmpty {
                Text("Nothing to preview yet.")
                    .font(.system(size: fontSize))
                    .foregroundStyle(Theme.secondaryText(scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                MarkdownPreview(text: text, title: title, fontSize: fontSize, scheme: scheme)
                    .padding(12)
            }
        }
    }
}
