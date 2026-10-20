import Foundation

/// Reads typed text the way Craft's markdown import does, so the capture
/// screens can preview what a note will become before it's sent.
///
/// The rules here were verified live against Craft's `blocks add --markdown`
/// (2026-10-19) rather than assumed — notably that consecutive plain lines
/// stay in ONE block (a soft line break) while a list item, heading or
/// divider is always its own block, that a plain line right after a list item
/// or quote continues it, and that `---` directly under a line makes it a
/// heading. Craft-only features (callouts, tables, toggles' children, ...)
/// are not covered, so a preview is close to, not identical to, Craft.
public enum CraftMarkdown {
    public enum Block: Equatable {
        /// Lines joined with "\n" (soft breaks within one block).
        case paragraph(String)
        case heading(level: Int, text: String)
        case bullet(level: Int, text: String)
        /// Craft renumbers ordered lists by position, so the typed digits are
        /// not kept — see `numbering(for:)`.
        case numbered(level: Int, text: String)
        case task(level: Int, done: Bool, text: String)
        case toggle(level: Int, text: String)
        case quote(String)
        case divider
        case code(String)
    }

    public static func parse(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        // True while the previous line belonged to a list item or quote that
        // a following plain line continues (CommonMark "lazy continuation").
        var canContinue = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph = []
        }

        func continueLast(with line: String) -> Bool {
            guard canContinue, let last = blocks.last else { return false }
            let i = blocks.count - 1
            switch last {
            case .bullet(let l, let t): blocks[i] = .bullet(level: l, text: t + "\n" + line)
            case .numbered(let l, let t): blocks[i] = .numbered(level: l, text: t + "\n" + line)
            case .task(let l, let d, let t): blocks[i] = .task(level: l, done: d, text: t + "\n" + line)
            case .toggle(let l, let t): blocks[i] = .toggle(level: l, text: t + "\n" + line)
            case .quote(let t): blocks[i] = .quote(t + "\n" + line)
            default: return false
            }
            return true
        }

        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            let line = lines[index]
            index += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                canContinue = false
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                canContinue = false
                var code: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 } // closing fence
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }

            // "---" / "===" directly under a text line turns that text into a
            // heading (verified: "x" over "---" became "## x").
            if !paragraph.isEmpty, matches(trimmed, #"^-{3,}$"#) || matches(trimmed, #"^={3,}$"#) {
                let level = trimmed.hasPrefix("-") ? 2 : 1
                blocks.append(.heading(level: level, text: paragraph.joined(separator: "\n")))
                paragraph = []
                canContinue = false
                continue
            }

            if matches(trimmed, #"^(\*{3,}|-{3,}|_{3,})$"#) {
                flushParagraph()
                blocks.append(.divider)
                canContinue = false
                continue
            }

            if let g = captures(trimmed, #"^(#{1,4})\s+(.+)$"#) {
                flushParagraph()
                blocks.append(.heading(level: g[0].count, text: g[1]))
                canContinue = false
                continue
            }

            if let g = captures(line, #"^(\s*)[-*]\s+\[([ xX])\]\s+(.*)$"#) {
                flushParagraph()
                blocks.append(.task(level: level(of: g[0]), done: g[1] != " ", text: g[2]))
                canContinue = true
                continue
            }
            if let g = captures(line, #"^(\s*)[-*]\s+(.*)$"#) {
                flushParagraph()
                blocks.append(.bullet(level: level(of: g[0]), text: g[1]))
                canContinue = true
                continue
            }
            if let g = captures(line, #"^(\s*)\+\s+(.*)$"#) {
                flushParagraph()
                blocks.append(.toggle(level: level(of: g[0]), text: g[1]))
                canContinue = true
                continue
            }
            if let g = captures(line, #"^(\s*)\d+[.)]\s+(.*)$"#) {
                flushParagraph()
                blocks.append(.numbered(level: level(of: g[0]), text: g[1]))
                canContinue = true
                continue
            }

            if let g = captures(trimmed, #"^>\s?(.*)$"#) {
                if canContinue, case .quote = blocks.last {
                    _ = continueLast(with: g[0])
                } else {
                    flushParagraph()
                    blocks.append(.quote(g[0]))
                }
                canContinue = true
                continue
            }

            // Plain text: continues a list item/quote it directly follows,
            // otherwise joins (or starts) a paragraph.
            if continueLast(with: trimmed) { continue }
            paragraph.append(trimmed)
            canContinue = false
        }
        flushParagraph()
        return blocks
    }

    /// The number to show for each block that is an ordered-list item, or nil
    /// for everything else. Craft renumbers by position (a typed "1. one /
    /// 1. two" shows as 1, 2), counting per indent level and restarting
    /// after anything that isn't part of the list.
    public static func numbering(for blocks: [Block]) -> [Int?] {
        var counters: [Int: Int] = [:]
        return blocks.map { block in
            switch block {
            case .numbered(let level, _):
                counters = counters.filter { $0.key <= level }
                counters[level, default: 0] += 1
                return counters[level]
            case .bullet(let level, _), .task(let level, _, _), .toggle(let level, _):
                counters = counters.filter { $0.key < level }
                return nil
            default:
                counters = [:]
                return nil
            }
        }
    }

    // MARK: - Helpers

    /// Two spaces (or one tab) per indent level, up to Craft's maximum of 5.
    private static func level(of indentation: String) -> Int {
        let spaces = indentation.filter { $0 == " " }.count
        let tabs = indentation.filter { $0 == "\t" }.count
        return min(5, spaces / 2 + tabs)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func captures(_ text: String, _ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<match.numberOfRanges).map { i in
            Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
