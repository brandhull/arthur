import Foundation

public enum CraftError: LocalizedError {
    case http(Int)
    case tool(String)
    case badResponse
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case .http(let code): return "Craft API returned HTTP \(code)"
        case .tool(let msg): return msg
        case .badResponse: return "Unexpected response from Craft"
        case .notConfigured: return "No Craft link set. Open Settings to paste your Craft MCP link."
        }
    }
}

/// Minimal MCP-over-HTTP client for Craft's link endpoint. The endpoint is
/// stateless — a bare JSON-RPC tools/call works with no initialize handshake —
/// and replies as a single-event SSE stream. Ported from craft-quick-capture's
/// CraftClient, extended with task commands for Arthur.
public struct CraftClient {
    public let url: String

    public init(url: String) {
        self.url = url
    }

    @discardableResult
    public func call(tool: String, command: String) async throws -> String {
        guard !url.isEmpty, let endpoint = URL(string: url) else {
            throw CraftError.notConfigured
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        // Bumped from 30 — the failure pattern Brandon reported (task
        // always lands in Craft in the right place, error every time, due
        // date never attaches) is the exact signature of the client giving
        // up on a slow response after the server already did the write:
        // the append's HTTP request succeeds server-side, but if the
        // response takes longer than this to come back, URLSession throws
        // a timeout before call() ever sees a body to parse — which also
        // means addTask's follow-up "attach the schedule" step never even
        // runs (confirmed via the task-add trace: "no update step
        // reached"), not that it silently fails. A generous timeout is a
        // no-risk change — it only makes the client wait longer before
        // giving up, no different behavior if the response was already
        // arriving inside 30s.
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": Int.random(in: 1...1_000_000),
            "method": "tools/call",
            "params": ["name": tool, "arguments": ["command": command]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw CraftError.http(http.statusCode)
        }

        let raw = String(decoding: data, as: UTF8.self)
        let candidates: [String]
        if raw.hasPrefix("{") {
            candidates = [raw]
        } else {
            candidates = raw.split(separator: "\n")
                .filter { $0.hasPrefix("data: ") }
                .map { String($0.dropFirst(6)) }
        }
        // Same diagnostic capture as the exhausted-candidates throw below —
        // this is a distinct empty-body/no-SSE-lines-at-all case that was
        // missing it. Brandon's task-add trace showed this throw fired
        // (append response logged as "not captured") but
        // craft_debug_last_failure.txt never appeared, because this guard
        // threw badResponse without ever calling logParseFailure — the only
        // covered throw site was the one at the bottom of this function.
        guard !candidates.isEmpty else {
            Self.logParseFailure(command: command, raw: raw)
            throw CraftError.badResponse
        }

        // Scan every SSE event, most recent first, and use whichever one
        // actually has the `result`/`content` shape — not a fixed position.
        // An earlier version of this assumed the events were "one
        // intermediate, one final" and took .last unconditionally, but that
        // just swapped which position could be wrong: a stream can also
        // carry a heartbeat/ping frame *after* the real result, which would
        // make .last wrong the same way .first was. Checking every
        // candidate for the actual expected shape — instead of guessing by
        // position — is what's actually reliable. Confirmed live: Brandon
        // added a task from the floating "+" button, it reached Craft
        // correctly (visible there, right place, right due date), but the
        // app still threw "Unexpected response from Craft" even after the
        // .last fix — same underlying instability, different position.
        for jsonText in candidates.reversed() {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [String: Any],
                  let result = obj["result"] as? [String: Any],
                  let content = result["content"] as? [[String: Any]],
                  let text = content.first?["text"] as? String
            else { continue }

            if (result["isError"] as? Bool) == true {
                throw CraftError.tool(text.components(separatedBy: "\n").first ?? text)
            }
            return text
        }
        // Diagnostic-only capture, no behavior change — Brandon reported
        // "Unexpected response from Craft" still happening specifically for
        // new tasks (not Quick Capture, not Rocks), even after the SSE
        // multi-event fix above. Since call() is shared by all three, the
        // remaining bug is more likely in addTask's own extra parsing
        // (appendBlocksReturningId's diff.after[0].id lookup) than here —
        // but there's no way to tell without seeing the actual raw response
        // that triggered it, and this MCP transport's SSE framing can't be
        // reproduced by calling Craft any other way. Writes the exact bytes
        // that failed to parse so the next real failure is inspectable
        // instead of guessed at again.
        Self.logParseFailure(command: command, raw: raw)
        throw CraftError.badResponse
    }

    /// See the comment above the only call site. Overwrites each time —
    /// this only needs to capture the most recent failure, not a history.
    private static func logParseFailure(command: String, raw: String) {
        let entry = "[\(Date())] command: \(command)\n\n\(raw)\n"
        try? entry.write(to: Config.supportDir.appendingPathComponent("craft_debug_last_failure.txt"),
                          atomically: true, encoding: .utf8)
    }

    // MARK: - Tasks

    /// Fetches a task scope ("active" = overdue+today, "upcoming" = tomorrow+,
    /// "inbox", "all", ...). `tasks list` only returns plain text — `--format
    /// json` is silently ignored as of the current MCP schema (confirmed
    /// 2026-07 against a live space) — so this parses the bullet-list format.
    /// A "No tasks found for scope ..." response is not an error; it just
    /// means an empty scope.
    public func listTasks(scope: String) async throws -> [CraftTask] {
        let text = try await call(tool: "craft_read", command: "tasks list --scope \(scope)")
        guard !text.hasPrefix("No tasks found") else { return [] }
        return CraftTask.parseList(text)
    }

    /// `tasks add` has no `--document`/destination flag (confirmed against
    /// the live MCP schema), so a specific destination goes through
    /// `blocks add` instead — which, unlike `tasks add`, returns the new
    /// block's ID in its response (`diff.after[0].id`, verified live 2026-07),
    /// letting a follow-up `tasks update` attach the schedule/deadline that
    /// `blocks add` itself can't set. Without this second step, a task added
    /// to a specific destination would silently lose its due date.
    public func addTask(markdown: String, schedule: String?, deadline: String?, destinationBlockId: String?) async throws {
        guard let destinationBlockId else {
            var command = "tasks add --markdown \(Self.craftQuote(markdown))"
            if let schedule { command += " --schedule \(schedule)" }
            if let deadline { command += " --deadline \(deadline)" }
            _ = try await call(tool: "craft_write", command: command)
            return
        }

        // Destination task-adds are a two-step chain (append, then update
        // for schedule/deadline) — each step is its own network round trip
        // with its own raw response. Logging only the step that happens to
        // throw loses the other step's body, and the append (where the id
        // comes from) is the more likely culprit even when the update is
        // what actually throws. So both raw bodies are captured into one
        // trace as they come in and written out together — always on
        // failure, whichever step fails — rather than each step logging in
        // isolation and overwriting the other.
        let taskMarkdown = "- [ ] " + markdown
        let appendCommand = "blocks add --id \(destinationBlockId) --markdown \(Self.craftQuote(taskMarkdown)) --position end"
        var rawUpdate: String?
        var updateCommand: String?
        do {
            let rawAppend = try await call(tool: "craft_write", command: appendCommand)
            guard let obj = try? JSONSerialization.jsonObject(with: Data(rawAppend.utf8)) as? [String: Any],
                  let diff = obj["diff"] as? [String: Any],
                  let after = diff["after"] as? [[String: Any]],
                  let newId = after.first?["id"] as? String else {
                Self.logTaskAddTrace(appendCommand: appendCommand, rawAppend: rawAppend,
                                      updateCommand: nil, rawUpdate: nil, caughtError: nil)
                throw CraftError.badResponse
            }
            guard schedule != nil || deadline != nil else { return }
            var update = "tasks update --id \(newId)"
            if let schedule { update += " --schedule \(schedule)" }
            if let deadline { update += " --deadline \(deadline)" }
            updateCommand = update
            rawUpdate = try await call(tool: "craft_write", command: update)
        } catch {
            Self.logTaskAddTrace(appendCommand: appendCommand, rawAppend: nil,
                                  updateCommand: updateCommand, rawUpdate: rawUpdate, caughtError: error)
            throw error
        }
    }

    /// See the comment above the only call site. Overwrites each time —
    /// captures whichever leg(s) of the append→update chain actually ran
    /// before the failure, so both are visible together instead of just
    /// the one that happened to throw.
    ///
    /// `caughtError` was missing entirely until Brandon's 2026-08-25 repro:
    /// the trace showed "append response: not captured" with no actual
    /// error text, because the outer catch block only logged raw bodies,
    /// never the thrown Error itself. That gap meant a whole category of
    /// failures was invisible — anything that throws before call() gets a
    /// chance to log (a raw URLSession error like a timeout, or
    /// CraftError.http), since those never touch craft_debug_last_failure.txt
    /// either. Confirmed live: that file genuinely didn't exist on disk for
    /// this failure, proving it wasn't a parse-failure at all. Recording
    /// the caught error's description directly is what actually answers
    /// "timeout vs HTTP error vs something else" going forward.
    private static func logTaskAddTrace(appendCommand: String, rawAppend: String?,
                                         updateCommand: String?, rawUpdate: String?,
                                         caughtError: Error?) {
        var entry = "[\(Date())] task-add trace\n\nappend command: \(appendCommand)\n"
        entry += "append response: \(rawAppend ?? "(not captured — call() already logged its own failure above)")\n\n"
        if let updateCommand {
            entry += "update command: \(updateCommand)\n"
            entry += "update response: \(rawUpdate ?? "(threw before returning — see the other debug file, craft_debug_last_failure.txt)")\n"
        } else {
            entry += "(no update step reached)\n"
        }
        if let caughtError {
            entry += "\ncaught error: \(caughtError)\n"
            entry += "localizedDescription: \(caughtError.localizedDescription)\n"
        }
        // Deliberately a separate file from craft_debug_last_failure.txt —
        // call() writes that one from *inside* this same failure (when the
        // failure is a generic SSE-parse miss), and this trace is written
        // from the catch block wrapping it. Sharing one filename would mean
        // whichever write happens second clobbers the other's detail,
        // exactly the "lost the other step's body" problem this exists to
        // avoid.
        try? entry.write(to: Config.supportDir.appendingPathComponent("craft_debug_task_trace.txt"),
                          atomically: true, encoding: .utf8)
    }

    /// Fetches a block's `craftdocs://open?...` deep link on demand (used by
    /// the long-press "open in Craft" gesture, not prefetched for every task
    /// on every refresh — keeps the common list-refresh path cheap).
    public func clickableLink(forBlockId id: String) async throws -> String {
        let text = try await call(tool: "craft_read", command: "blocks get \(id) --fetchMetadata --format json")
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let data = obj["data"] as? [[String: Any]],
              let first = data.first,
              let metadata = first["metadata"] as? [String: Any],
              let link = metadata["clickableLink"] as? String else {
            throw CraftError.badResponse
        }
        return link
    }

    public func setTaskState(id: String, state: String) async throws {
        _ = try await call(tool: "craft_write", command: "tasks update --id \(id) --state \(state)")
    }

    public func updateTaskText(id: String, markdown: String) async throws {
        _ = try await call(tool: "craft_write",
                           command: "tasks update --id \(id) --markdown \(Self.craftQuote(markdown))")
    }

    /// `date` is `yyyy-MM-dd` (or Craft's own relative keywords). Verified
    /// live against a real task with `tasks update --id ... --schedule ...`
    /// — the flag exists on update, not just on `tasks add`.
    public func updateTaskSchedule(id: String, date: String) async throws {
        _ = try await call(tool: "craft_write", command: "tasks update --id \(id) --schedule \(date)")
    }

    // MARK: - Daily note

    public func appendBlocksToDailyNote(day: String, markdown: String) async throws {
        let quoted = Self.craftQuote(markdown)
        _ = try await call(tool: "craft_write",
                           command: "blocks add --date \(day) --markdown \(quoted) --position end")
    }

    public func dailyNoteMarkdown(day: String) async throws -> String {
        do {
            let text = try await call(tool: "craft_read", command: "blocks get --date \(day) --format markdown")
            return Self.extractPageContent(text)
        } catch CraftError.tool(let message) where message.localizedCaseInsensitiveContains("does not exist") {
            // Craft only wraps a page in <page>/<content> tags once it has
            // been created — a date with no note at all (the common case,
            // since Brandon rarely writes one) errors instead of returning
            // an empty page. That's a normal "nothing here yet" state for
            // this call specifically, not a failure worth alerting on.
            return ""
        }
    }

    /// Same read as `dailyNoteMarkdown`, but for any page by rootBlockId
    /// (Rocks, or any other single-page document Arthur reads/edits in
    /// place) rather than a date-keyed daily note.
    public func pageMarkdown(rootBlockId: String) async throws -> String {
        let text = try await call(tool: "craft_read", command: "blocks get \(rootBlockId) --format markdown")
        return Self.extractPageContent(text)
    }

    /// `blocks get --format markdown` always wraps its response in the
    /// page's own structural tags (`<page id="..."><pageTitle>...
    /// </pageTitle><content>...actual note text...</content></page>`) —
    /// not just when the page is empty. Verified live 2026-07 with real note
    /// content present: the wrapper is still there around it, not only
    /// around an empty page. This pulls out just the `<content>` text
    /// (de-indenting it — Craft nests it under the tag) so the UI shows the
    /// real note, not the surrounding markup. No `<content>` tag at all means
    /// the page has no blocks yet, which correctly resolves to "" (shows the
    /// empty-state placeholder). Shared by dailyNoteMarkdown and pageMarkdown
    /// — not daily-note-specific despite the name history.
    static func extractPageContent(_ text: String) -> String {
        guard let openRange = text.range(of: "<content>"),
              let closeRange = text.range(of: "</content>", range: openRange.upperBound..<text.endIndex)
        else { return "" }
        let inner = text[openRange.upperBound..<closeRange.lowerBound]
        let lines = inner.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A page's direct child blocks (id + markdown each), used by
    /// `replacePageContent` to know what to delete. Empty array for a page
    /// with no content yet (no `content` key at all in that case, not an
    /// empty array — confirmed against Rocks live, which currently has zero
    /// blocks).
    public struct CraftBlock {
        public let id: String
        public let markdown: String
    }

    public func pageBlocks(rootBlockId: String) async throws -> [CraftBlock] {
        let text = try await call(tool: "craft_read", command: "blocks get \(rootBlockId) --format json")
        return Self.parseBlocks(text)
    }

    /// A document's own direct sub-pages (nested `type: "page"` blocks) —
    /// `documents list` never surfaces these, since Craft's document tree
    /// only contains top-level, folder-organized documents; a sub-page is
    /// just a block living inside its parent's content, invisible to that
    /// command at any depth (confirmed live: `documents list --filter`
    /// against a known sub-page title, "1:1s", returned nothing). `--depth
    /// 1` keeps this to one level — Brandon: "99 times out of 100 I will
    /// know the parent page," so Quick Capture's destination search finds
    /// the parent by name as before, and this just lists what's directly
    /// inside it, not a recursive crawl of the whole space.
    public func subPages(of rootBlockId: String) async throws -> [CraftBlock] {
        let text = try await call(tool: "craft_read", command: "blocks get \(rootBlockId) --depth 1 --format json")
        return Self.parseBlocks(text, typeFilter: "page")
    }

    /// Same shape as `pageBlocks`, but for the date-keyed daily note rather
    /// than a resolved rootBlockId.
    private func dailyNoteBlocks(day: String) async throws -> [CraftBlock] {
        do {
            let text = try await call(tool: "craft_read", command: "blocks get --date \(day) --format json")
            return Self.parseBlocks(text)
        } catch CraftError.tool(let message) where message.localizedCaseInsensitiveContains("does not exist") {
            // Same "no note yet" tolerance as dailyNoteMarkdown, for the
            // same reason — a date with no note errors instead of
            // returning empty. This one matters even more: it's on the
            // save path (replaceDailyNoteContent calls this first, to find
            // existing blocks to delete before writing the new content),
            // so without it, saving a Reflection for the very first time
            // on a given day always threw — Brandon caught this hitting
            // Edit -> Save on a day with nothing there yet. No existing
            // blocks for a day with no note is correct as an empty array,
            // not an error.
            return []
        }
    }

    private static func parseBlocks(_ text: String, typeFilter: String? = nil) -> [CraftBlock] {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let data = obj["data"] as? [[String: Any]],
              let content = data.first?["content"] as? [[String: Any]]
        else { return [] }
        return content.compactMap { block in
            guard let id = block["id"] as? String, let md = block["markdown"] as? String else { return nil }
            if let typeFilter, block["type"] as? String != typeFilter { return nil }
            return CraftBlock(id: id, markdown: md)
        }
    }

    /// Replaces a page's entire content with `markdown` — used by Rocks'
    /// "Edit" flow. There's no single "replace all" API call: `blocks
    /// update` only replaces one existing block and would leave stale
    /// leftover blocks behind if the edited text has fewer blocks than
    /// before, so this deletes every existing child block first, then adds
    /// the new text fresh. More round-trips than a single call, but
    /// correct regardless of how the block count changed.
    public func replacePageContent(rootBlockId: String, markdown: String) async throws {
        let existing = try await pageBlocks(rootBlockId: rootBlockId)
        for block in existing {
            _ = try await call(tool: "craft_write", command: "blocks delete --id \(block.id)")
        }
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await appendBlocks(pageId: rootBlockId, markdown: trimmed)
    }

    /// Same as `replacePageContent`, but for the daily note — used by
    /// Reflection's "Edit" flow. The add step reuses `appendBlocksToDailyNote`
    /// (date-keyed, no id needed); only the delete step needs each existing
    /// block's own id.
    public func replaceDailyNoteContent(day: String, markdown: String) async throws {
        let existing = try await dailyNoteBlocks(day: day)
        for block in existing {
            _ = try await call(tool: "craft_write", command: "blocks delete --id \(block.id)")
        }
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await appendBlocksToDailyNote(day: day, markdown: trimmed)
    }

    // MARK: - Documents (inbox destinations)

    public func appendBlocks(pageId: String, markdown: String) async throws {
        let quoted = Self.craftQuote(markdown)
        _ = try await call(tool: "craft_write",
                           command: "blocks add --id \(pageId) --markdown \(quoted) --position end")
    }

    /// One-time setup: turns a pasted Craft doc URL into a stable rootBlockId.
    public func resolveLink(_ craftURL: String) async throws -> String {
        let text = try await call(tool: "craft_read",
                                  command: "documents resolve-link \(craftURL)")
        // Response is the rootBlockId, possibly with surrounding text; grab the
        // first UUID-looking token.
        let regex = try NSRegularExpression(pattern: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f-]{27,}"#)
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range), let r = Range(m.range, in: text) else {
            throw CraftError.badResponse
        }
        return String(text[r])
    }

    // MARK: - Document listing (floating capture button's "choose a page")

    /// Every document, tagged with its folder name — ported from
    /// craft-quick-capture's listAllDocuments, trimmed to single-space.
    public func listAllDocuments() async throws -> [CraftDocument] {
        var docs: [CraftDocument] = []
        var seen = Set<String>()
        for folder in try await listFolders() {
            try await page(command: "documents list --folder \(folder.id)",
                           folderName: folder.name, into: &docs, seen: &seen)
        }
        try await page(command: "documents list", folderName: nil, into: &docs, seen: &seen)
        return docs
    }

    /// Resolves a document by exact title within a named folder (e.g. "Rocks"
    /// in "Personal") — used to find Rocks without a Settings field, since
    /// Craft has no direct "find doc by title+folder" command. Only searches
    /// that one folder's documents, not the whole space, so it stays quick
    /// even with a large space. Throws a clear, specific error if either the
    /// folder or the title within it can't be found, since a silent nil here
    /// would just look like Rocks was empty rather than misconfigured.
    public func resolveDocument(title: String, folder: String) async throws -> String {
        let folders = try await listFolders()
        guard let match = folders.first(where: { $0.name.caseInsensitiveCompare(folder) == .orderedSame }) else {
            throw CraftError.tool("No folder named \"\(folder)\" found in Craft.")
        }
        var docs: [CraftDocument] = []
        var seen = Set<String>()
        try await page(command: "documents list --folder \(match.id)", folderName: match.name, into: &docs, seen: &seen)
        guard let doc = docs.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) else {
            throw CraftError.tool("No document named \"\(title)\" found in the \"\(folder)\" folder.")
        }
        return doc.id
    }

    private func listFolders() async throws -> [(id: String, name: String)] {
        let text = try await call(tool: "craft_read", command: "folders list")
        let regex = try NSRegularExpression(pattern: #"<([0-9A-Fa-f-]+)>\s+(.+?)\s+\(\d+ docs?\)"#)
        var folders: [(id: String, name: String)] = []
        for line in text.split(separator: "\n") {
            let s = String(line)
            let range = NSRange(s.startIndex..., in: s)
            guard let m = regex.firstMatch(in: s, range: range),
                  let idR = Range(m.range(at: 1), in: s),
                  let nameR = Range(m.range(at: 2), in: s) else { continue }
            folders.append((id: String(s[idR]), name: String(s[nameR])))
        }
        return folders
    }

    private func page(command baseCommand: String, folderName: String?,
                      into docs: inout [CraftDocument], seen: inout Set<String>) async throws {
        var command = baseCommand
        let lineRegex = try NSRegularExpression(pattern: #"^\s*<([0-9A-Fa-f-]+)>\s+(.+)$"#)
        for _ in 0..<40 { // safety valve: 40 pages ≈ 2000 docs
            let text = try await call(tool: "craft_read", command: command)
            var nextCursor: String?
            for line in text.split(separator: "\n") {
                let s = String(line)
                if s.hasPrefix("Next page:"), let range = s.range(of: "--cursor ") {
                    nextCursor = String(s[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    continue
                }
                let range = NSRange(s.startIndex..., in: s)
                guard let m = lineRegex.firstMatch(in: s, range: range),
                      let idR = Range(m.range(at: 1), in: s),
                      let titleR = Range(m.range(at: 2), in: s) else { continue }
                let id = String(s[idR])
                guard seen.insert(id).inserted else { continue }
                docs.append(CraftDocument(id: id,
                                          title: String(s[titleR]).trimmingCharacters(in: .whitespaces),
                                          folder: folderName))
            }
            guard let cursor = nextCursor else { break }
            command = "\(baseCommand) --cursor \(cursor)"
        }
    }

    public static func craftQuote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
