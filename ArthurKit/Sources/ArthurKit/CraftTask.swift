import Foundation

public struct CraftTask: Identifiable, Hashable {
    public let id: String
    public var text: String
    public var done: Bool
    public var containerTitle: String?   // the "in: X" line — document/section this task lives in
    public var containerId: String?
    public var scheduleDate: Date?
    public var deadlineDate: Date?
    public var clickableLink: String?    // craftdocs://open?... fetched lazily via blocks get --fetchMetadata

    public init(id: String, text: String, done: Bool, containerTitle: String? = nil,
                containerId: String? = nil, scheduleDate: Date? = nil, deadlineDate: Date? = nil,
                clickableLink: String? = nil) {
        self.id = id
        self.text = text
        self.done = done
        self.containerTitle = containerTitle
        self.containerId = containerId
        self.scheduleDate = scheduleDate
        self.deadlineDate = deadlineDate
        self.clickableLink = clickableLink
    }

    /// The date used for Overdue/Today/Tomorrow bucketing: schedule, else deadline.
    public var taskDate: Date? { scheduleDate ?? deadlineDate }
}

/// "All" and "Overdue" as separate filters are gone — Brandon: "this app is
/// for quick use of tasks in Craft, not exhaustive use... I'll just go to
/// the Craft app for that." Today now absorbs Overdue (anything due today
/// or earlier), leaving just two filters instead of four.
public enum TaskFilter: String, CaseIterable, Identifiable, Hashable {
    case today = "Today"
    case tomorrow = "Tomorrow"
    public var id: String { rawValue }
}

public enum TaskBucketing {
    public static func matches(_ task: CraftTask, filter: TaskFilter, now: Date = Date()) -> Bool {
        let cal = Calendar.current
        switch filter {
        case .today:
            // <= today, not isDate(inSameDayAs:) — this is what absorbs the
            // old separate "Overdue" filter into Today.
            guard let d = task.taskDate else { return false }
            return cal.startOfDay(for: d) <= cal.startOfDay(for: now)
        case .tomorrow:
            guard let d = task.taskDate,
                  let tomorrow = cal.date(byAdding: .day, value: 1, to: now) else { return false }
            return cal.isDate(d, inSameDayAs: tomorrow)
        }
    }
}

extension CraftTask {
    /// Parses the plain-text line format `tasks list` returns:
    ///   [ ] <ID> - [ ] task text
    ///     (schedule: 2026-07-24, deadline: 2026-07-25)   — optional, either/both/neither
    ///     in: Container Name <containerId>
    /// (No JSON output mode is available for `tasks list` as of the current
    /// MCP schema — confirmed 2026-07 against a live space; --format json is
    /// silently ignored. The `(schedule: ...)`/`(deadline: ...)` line is
    /// optional and, when present, sits *between* the header and the "in:"
    /// line — verified live 2026-07 against real scheduled/deadlined test
    /// tasks. An earlier version of this parser assumed "in:" always
    /// immediately follows the header, which silently dropped both the dates
    /// and the container whenever that metadata line was present.)
    public static func parseList(_ text: String) -> [CraftTask] {
        var tasks: [CraftTask] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let headerRegex = try! NSRegularExpression(
            pattern: #"^\[( |x)\]\s+<([0-9A-Za-z-]+)>\s+-\s+\[( |x)\]\s+(.+)$"#)
        let datesRegex = try! NSRegularExpression(
            pattern: #"^\s+\((?:schedule: (\d{4}-\d{2}-\d{2}))?(?:, )?(?:deadline: (\d{4}-\d{2}-\d{2}))?\)$"#)
        let containerRegex = try! NSRegularExpression(
            pattern: #"^\s+in:\s+(.+?)(?:\s+<([0-9A-Za-z-]+)>)?$"#)
        let dayFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = .current
            return f
        }()

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let range = NSRange(line.startIndex..., in: line)
            if let m = headerRegex.firstMatch(in: line, range: range),
               let idR = Range(m.range(at: 2), in: line),
               let textR = Range(m.range(at: 4), in: line) {
                let done = (Range(m.range(at: 1), in: line).map { String(line[$0]) } == "x")
                var task = CraftTask(id: String(line[idR]), text: String(line[textR]), done: done)
                var j = i + 1

                if j < lines.count {
                    let candidate = lines[j]
                    let cRange = NSRange(candidate.startIndex..., in: candidate)
                    if let dm = datesRegex.firstMatch(in: candidate, range: cRange) {
                        if let schedR = Range(dm.range(at: 1), in: candidate) {
                            task.scheduleDate = dayFormatter.date(from: String(candidate[schedR]))
                        }
                        if let deadR = Range(dm.range(at: 2), in: candidate) {
                            task.deadlineDate = dayFormatter.date(from: String(candidate[deadR]))
                        }
                        j += 1
                    }
                }

                if j < lines.count {
                    let next = lines[j]
                    let nRange = NSRange(next.startIndex..., in: next)
                    if let cm = containerRegex.firstMatch(in: next, range: nRange),
                       let titleR = Range(cm.range(at: 1), in: next) {
                        task.containerTitle = String(next[titleR]).trimmingCharacters(in: .whitespaces)
                        if let idR2 = Range(cm.range(at: 2), in: next) {
                            task.containerId = String(next[idR2])
                        }
                        j += 1
                    }
                }

                tasks.append(task)
                i = j
                continue
            }
            i += 1
        }
        return tasks
    }
}
