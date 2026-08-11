import Foundation
import ArthurKit
import SwiftUI

@MainActor
final class TaskStore: ObservableObject {
    @Published var tasks: [CraftTask] = []
    @Published var filter: TaskFilter = .today
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var config: Config = Config.load()

    // Daily note: the current note is fetched read-only from Craft; new text
    // is appended explicitly via the "Add" button rather than autosaved as you
    // type (per Brandon's UX feedback — replaces the earlier always-editable
    // autosave box).
    @Published var dailyNoteContent: String = ""
    @Published var dailyNoteLoading = false
    @Published var dailyNoteSaving = false

    // Rocks: same fetched-read-only-by-default pattern as the daily note,
    // plus a full edit/replace flow the daily note also gets (see
    // saveDailyNote below) — Brandon wants to edit both in place, not just
    // append to them.
    @Published var rocksContent: String = ""
    @Published var rocksLoading = false
    @Published var rocksSaving = false

    private var client: CraftClient { CraftClient(url: config.craftLink) }

    /// Guards the scenePhase-triggered refetch in AgendaView — same
    /// staleness-gate idea as DocumentStore.refreshIfStale. Without this,
    /// every `.active` transition re-ran refresh()+loadDailyNote()+
    /// loadRocks() (three Craft round-trips) unconditionally, and on Mac
    /// specifically, scenePhase flips to `.active` on every window refocus,
    /// not just a cold launch or a return from the background the way it
    /// does on iOS. With Arthur meant to stay open all day and get
    /// alt-tabbed in and out of constantly, that was a refetch on every
    /// single click back into the window — most of which land seconds or
    /// minutes apart, well within any reasonable staleness window.
    private var lastActiveRefresh: Date?

    /// Mirrors DocumentStore.refreshIfStale's signature/naming on purpose —
    /// same pattern, same reason to exist.
    func refreshIfStale(maxAge: TimeInterval = 90) async {
        if let lastActiveRefresh, Date().timeIntervalSince(lastActiveRefresh) < maxAge { return }
        lastActiveRefresh = Date()
        await refresh()
        await loadDailyNote()
        await loadRocks()
    }

    var filteredTasks: [CraftTask] {
        tasks.filter { !$0.done && TaskBucketing.matches($0, filter: filter) }
    }

    func reloadConfig() {
        config = Config.load()
    }

    func refresh() async {
        guard config.isConfigured else {
            errorMessage = CraftError.notConfigured.localizedDescription
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // "all", not active+upcoming+inbox merged — those three only
            // return a task if it has a schedule/deadline date (active/
            // upcoming) or lives in Craft's bare inbox specifically. Tasks
            // sitting in regular documents with no date fell through all
            // three gaps entirely, which is why "All" was showing far fewer
            // tasks than Brandon actually has in Craft.
            tasks = try await client.listTasks(scope: "all")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleDone(_ task: CraftTask) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let previousDone = tasks[idx].done
        let newDone = !previousDone
        tasks[idx].done = newDone
        Task {
            do {
                try await client.setTaskState(id: task.id, state: newDone ? "done" : "todo")
            } catch {
                handleTaskWriteFailure(taskId: task.id, error: error) {
                    if let revertIdx = tasks.firstIndex(where: { $0.id == task.id }) {
                        tasks[revertIdx].done = previousDone
                    }
                }
            }
        }
    }

    /// `tasks list` doesn't expose whether a task's document is in Craft's
    /// trash — the only way Arthur finds out is when a write against it
    /// fails. Rather than just reverting the optimistic UI change and
    /// leaving the (permanently broken) task sitting in the list, drop it
    /// from `tasks` entirely once we learn this — same end result Brandon
    /// gets for done tasks (filtered out of view), just discovered
    /// reactively instead of up front. `revertIfNotTrashed` still runs for
    /// any other kind of failure (network blip, etc.), where the task is
    /// still valid and the UI should just show its prior state again.
    private func handleTaskWriteFailure(taskId: String, error: Error, revertIfNotTrashed: () -> Void) {
        let isTrashed = error.localizedDescription.localizedCaseInsensitiveContains("trash")
        if isTrashed {
            tasks.removeAll { $0.id == taskId }
            errorMessage = "That task's document is in Craft's trash, so it's been removed from this list. Restore it in Craft to bring it back."
        } else {
            revertIfNotTrashed()
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches the Craft deep link for one task on demand (long-press "open in
    /// Craft" gesture) rather than prefetching it for every task on refresh.
    func clickableLink(for task: CraftTask) async -> URL? {
        if let cached = task.clickableLink, let url = URL(string: cached) { return url }
        do {
            let link = try await client.clickableLink(forBlockId: task.id)
            return URL(string: link)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateText(_ task: CraftTask, newText: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let previousText = tasks[idx].text
        tasks[idx].text = newText
        Task {
            do {
                try await client.updateTaskText(id: task.id, markdown: newText)
            } catch {
                handleTaskWriteFailure(taskId: task.id, error: error) {
                    if let revertIdx = tasks.firstIndex(where: { $0.id == task.id }) {
                        tasks[revertIdx].text = previousText
                    }
                }
            }
        }
    }

    /// Only updates `scheduleDate` — Arthur's inline picker edits the one
    /// date shown in the row (schedule, falling back to deadline only for
    /// display via `taskDate`), and `updateTaskSchedule` only has a
    /// `--schedule` flag to begin with (confirmed live against the real
    /// Craft API; no separate deadline-update path was tested or needed).
    func updateDueDate(_ task: CraftTask, newDate: Date) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let previousDate = tasks[idx].scheduleDate
        tasks[idx].scheduleDate = newDate
        Task {
            do {
                try await client.updateTaskSchedule(id: task.id, date: Self.isoDay(newDate))
            } catch {
                handleTaskWriteFailure(taskId: task.id, error: error) {
                    if let revertIdx = tasks.firstIndex(where: { $0.id == task.id }) {
                        tasks[revertIdx].scheduleDate = previousDate
                    }
                }
            }
        }
    }

    func addTask(text: String, dueDate: Date?, destination: InboxDestination?) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let schedule = dueDate.map { Self.isoDay($0) }
        Task {
            do {
                try await client.addTask(markdown: text, schedule: schedule, deadline: nil,
                                          destinationBlockId: destination?.id)
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    static func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }

    // MARK: - Daily note

    func loadDailyNote() async {
        guard config.isConfigured else {
            errorMessage = CraftError.notConfigured.localizedDescription
            return
        }
        dailyNoteLoading = true
        defer { dailyNoteLoading = false }
        do {
            dailyNoteContent = try await client.dailyNoteMarkdown(day: "today")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Appends `text` to today's note (the "Add" button flow), then reloads
    /// the displayed content so it reflects what's actually in Craft.
    func appendToDailyNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, config.isConfigured else { return }
        dailyNoteSaving = true
        Task {
            defer { dailyNoteSaving = false }
            do {
                try await client.appendBlocksToDailyNote(day: "today", markdown: text)
                await loadDailyNote()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Replaces the whole daily note's content — Reflection's "Edit" flow,
    /// as opposed to appendToDailyNote's "Add" flow above.
    func saveDailyNote(_ newContent: String) {
        dailyNoteSaving = true
        Task {
            defer { dailyNoteSaving = false }
            do {
                try await client.replaceDailyNoteContent(day: "today", markdown: newContent)
                dailyNoteContent = newContent
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Clears any stale error before syncing, so a message from a previous
    /// failure doesn't linger and get misread as describing this attempt —
    /// and so a real failure here isn't silently masked by the other call's
    /// success (both refresh() and loadDailyNote() write to the same
    /// errorMessage; whichever fails last wins, which is fine since this
    /// button's whole point is "did *this* sync work or not").
    func forceSync() async {
        errorMessage = nil
        lastActiveRefresh = Date()
        await refresh()
        await loadDailyNote()
        // Rocks was missing here — a manual pull-to-refresh silently left
        // Rocks stale while refreshing everything else, unlike cold launch
        // and the scenePhase-active refetch, which both already include it.
        await loadRocks()
    }

    // MARK: - Rocks

    func loadRocks() async {
        guard config.isConfigured else {
            errorMessage = CraftError.notConfigured.localizedDescription
            return
        }
        rocksLoading = true
        defer { rocksLoading = false }
        do {
            rocksContent = try await rocksDocumentOperation { try await client.pageMarkdown(rootBlockId: $0) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveRocks(_ newContent: String) {
        rocksSaving = true
        Task {
            defer { rocksSaving = false }
            do {
                try await rocksDocumentOperation { try await client.replacePageContent(rootBlockId: $0, markdown: newContent) }
                rocksContent = newContent
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Resolves "Rocks" in the "Personal" folder once and caches the id in
    /// Config so Arthur doesn't re-search the folder on every launch. If an
    /// operation using the cached id fails (doc renamed/moved since it was
    /// cached), clears the cache and retries once with a fresh resolve
    /// before giving up — so a stale cache degrades to one extra round-trip
    /// rather than a permanent failure.
    private func rocksDocumentOperation<T>(_ operation: (String) async throws -> T) async throws -> T {
        let docId: String
        if let cached = config.rocksDocumentId {
            docId = cached
        } else {
            docId = try await client.resolveDocument(title: "Rocks", folder: "Personal")
            config.rocksDocumentId = docId
            config.save()
        }
        do {
            return try await operation(docId)
        } catch {
            config.rocksDocumentId = nil
            let freshId = try await client.resolveDocument(title: "Rocks", folder: "Personal")
            config.rocksDocumentId = freshId
            config.save()
            return try await operation(freshId)
        }
    }
}
