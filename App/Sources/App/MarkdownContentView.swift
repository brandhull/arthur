import SwiftUI

/// Lightweight block-level markdown renderer for read-only display of a
/// Craft page's content (Rocks, Reflection). SwiftUI's own `Text(markdown:)`
/// only understands *inline* markdown (bold/italic/code/links), not block
/// syntax like "#### Heading" or "- bullet" — those showed up as literal
/// "####"/"- " characters otherwise (Brandon caught this on Rocks, which
/// stores each priority as its own h4 heading block). This handles the
/// block syntax Craft's markdown export actually produces — headings
/// (#-####), bullets (-/*), numbered lists, and blockquotes (>) — falling
/// back to a plain paragraph (still inline-markdown-aware, so **bold**
/// etc. still works within it) for everything else.
struct MarkdownContentView: View {
    let markdown: String
    let scheme: ColorScheme

    private struct Line: Identifiable {
        let id = UUID()
        let text: AttributedString
        let style: Style
    }

    private enum Style {
        case heading(Int)
        case bullet
        case numbered(Int)
        case quote
        case paragraph
    }

    // One line = one block, matching Craft's own model (each block is its
    // own line once fetched as markdown) — blank lines are just the gaps
    // between blocks, not content of their own.
    private var lines: [Line] {
        markdown
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map(Self.parseLine)
    }

    private static func parseLine(_ raw: String) -> Line {
        var content = raw.trimmingCharacters(in: .whitespaces)
        var style: Style = .paragraph

        if let match = content.range(of: #"^#{1,4} "#, options: .regularExpression) {
            let level = content.distance(from: content.startIndex, to: match.upperBound) - 1
            style = .heading(level)
            content = String(content[match.upperBound...])
        } else if content.hasPrefix("- ") || content.hasPrefix("* ") {
            style = .bullet
            content = String(content.dropFirst(2))
        } else if let match = content.range(of: #"^\d+\. "#, options: .regularExpression) {
            let number = Int(content[content.startIndex..<match.upperBound]
                .trimmingCharacters(in: CharacterSet(charactersIn: ". "))) ?? 1
            style = .numbered(number)
            content = String(content[match.upperBound...])
        } else if content.hasPrefix("> ") {
            style = .quote
            content = String(content.dropFirst(2))
        }

        let attributed = (try? AttributedString(markdown: content,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnly)))
            ?? AttributedString(content)
        return Line(text: attributed, style: style)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(lines) { line in render(line) }
        }
    }

    @ViewBuilder
    private func render(_ line: Line) -> some View {
        switch line.style {
        case .heading(let level):
            Text(line.text)
                .font(.system(size: headingSize(for: level), weight: .semibold))
                .foregroundStyle(Theme.primary(scheme))
        case .bullet:
            HStack(alignment: .top, spacing: 8) {
                Text("•").font(.system(size: 15))
                Text(line.text).font(.system(size: 15)).lineSpacing(3)
            }
            .foregroundStyle(Theme.primary(scheme))
        case .numbered(let n):
            HStack(alignment: .top, spacing: 8) {
                Text("\(n).").font(.system(size: 15))
                Text(line.text).font(.system(size: 15)).lineSpacing(3)
            }
            .foregroundStyle(Theme.primary(scheme))
        case .quote:
            Text(line.text)
                .font(.system(size: 15))
                .italic()
                .lineSpacing(3)
                .foregroundStyle(Theme.secondaryText(scheme))
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Theme.primary(scheme).opacity(0.3)).frame(width: 2)
                }
        case .paragraph:
            Text(line.text)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(Theme.primary(scheme))
        }
    }

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return 22
        case 2: return 19
        case 3: return 17
        default: return 16
        }
    }
}
