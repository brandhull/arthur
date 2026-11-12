import SwiftUI
import ArthurKit

/// The one capture screen. A big blank text box fills the pane; the
/// Destination card docked at the bottom chooses where it goes: an existing
/// Craft page (search, with sub-pages), a new Craft page in any folder or
/// sub-folder, today's Reflection, a Bit, a Craft task, or a Baserow row.
/// Everything except Baserow shares the same text box; Baserow swaps the pane
/// for its form (anything already typed carries into the first long-text
/// field). Save sits above the card so a capture never needs it expanded.
struct QuickCaptureView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var documentStore: DocumentStore
    @EnvironmentObject var draft: QuickCaptureDraft
    @ObservedObject var outbox: OutboxStore
    /// Sends a Bit / appends to today's note; nil on success, else an error
    /// message. Provided by AgendaView, which owns those stores (and the
    /// offline-queue fallbacks).
    let saveBit: (String) async -> String?
    let saveReflection: (String) async -> String?
    @Environment(\.colorScheme) private var systemScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// True whenever the Quick Capture tab itself is the selected one — the
    /// edge-trigger for auto-focusing the text box on Mac.
    let isActive: Bool

    /// True while the top bar's preview toggle is on: the capture box shows
    /// the text rendered as Craft will receive it instead of the editor.
    let isPreviewing: Bool

    /// Whether the Destination card is expanded. Starts collapsed so the app
    /// opens straight into a clean typing surface. Owned by AgendaView.
    @Binding var isDestinationExpanded: Bool

    // MARK: Craft state
    // craftText/addSeparator used to be local @State here — now they live
    // on the shared `draft` (QuickCaptureDraft) instead (see that type's own
    // comment for why this is still an environment object).
    @State private var query = ""
    @State private var selectedDoc: CraftDocument?
    @State private var isCraftSubmitting = false
    @State private var craftErrorMessage: String?

    // MARK: Sub-page picker (see loadSubPages)
    @State private var subPages: [CraftClient.CraftBlock] = []
    @State private var subPagesParentId: String?
    @State private var isLoadingSubPages = false

    // MARK: Baserow state
    @State private var databaseId: Int?
    @State private var tableId: Int?
    @State private var tables: [BaserowTable] = []
    @State private var fields: [BaserowField] = []
    @State private var textValues: [Int: String] = [:]
    @State private var boolValues: [Int: Bool] = [:]
    @State private var multiSelectValues: [Int: Set<String>] = [:]
    @State private var dateValues: [Int: Date] = [:]
    @State private var includeDateFields: Set<Int> = []
    @State private var isLoadingTables = false
    @State private var isLoadingFields = false
    @State private var isBaserowSubmitting = false
    @State private var baserowErrorMessage: String?
    /// Which load failed, so the error can offer a Retry for exactly that one.
    @State private var loadFailure: LoadFailure?

    private enum LoadFailure { case tables, fields }

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    // MARK: New-page / task / status state
    @State private var folderQuery = ""
    @State private var selectedFolder: CraftFolder?
    @State private var allFolders: [CraftFolder] = []
    @State private var isLoadingFolders = false
    // A page created by a submit whose body append then failed — a retry with
    // the same title/folder reuses it instead of creating a second page.
    @State private var pendingPage: (id: String, title: String, folderId: String)?
    @State private var includeDueDate = false
    @State private var dueDate = Date()
    @State private var taskInboxId: String?
    @State private var statusMessage: String?
    @State private var didApplyDefaultTarget = false

    private var results: [CraftDocument] { documentStore.search(query) }

    private var target: CaptureTarget { draft.target }

    private var effectiveScheme: ColorScheme {
        Theme.effectiveScheme(appearance: store.config.appearance, system: systemScheme)
    }

    private var inputFontSize: CGFloat {
        #if os(iOS)
        return Theme.inputFontSize(horizontalSizeClass: horizontalSizeClass)
        #else
        return Theme.inputFontSize()
        #endif
    }

    private var baserowClient: BaserowClient {
        BaserowClient(token: store.config.baserowToken)
    }

    /// The destination chosen in Settings (Append Craft Page unless changed).
    private var defaultTarget: CaptureTarget {
        CaptureTarget(rawValue: store.config.defaultCaptureTarget ?? "") ?? .page
    }

    private func handleOnAppear() {
        if !didApplyDefaultTarget {
            didApplyDefaultTarget = true
            draft.target = defaultTarget
        }
        documentStore.refreshIfStale(craftLink: store.config.craftLink)
        loadFolders()
    }

    private var destinationCardHorizontalInset: CGFloat {
        #if os(macOS)
        return Theme.sidebarCardInset
        #else
        return 16
        #endif
    }

    // MARK: - Derived text

    private var trimmedText: String { draft.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// First non-empty line becomes a new page's title; the rest is its body.
    private var titleAndBody: (title: String, body: String) {
        let lines = draft.text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let title = lines.first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        let body = lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .newlines) : ""
        return (title, body)
    }

    private var canSave: Bool {
        switch target {
        case .page: return !trimmedText.isEmpty && selectedDoc != nil
        case .newPage: return !titleAndBody.title.isEmpty && selectedFolder != nil
        case .reflection, .bits, .task: return !trimmedText.isEmpty
        case .baserow: return false
        }
    }

    /// iPhone only: the narrow Destination bar and picker use short names.
    private var useShortNames: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    private func name(_ target: CaptureTarget) -> String {
        useShortNames ? target.shortName : target.rawValue
    }

    /// What the collapsed Destination bar shows next to its title: the
    /// destination type (never truncated) and, once chosen, the page / folder
    /// / table after it (this is the part that gives way when space is tight).
    private var summaryDetail: String? {
        switch target {
        case .page: return selectedDoc?.title
        case .newPage: return selectedFolder?.name
        case .baserow: return tables.first(where: { $0.id == tableId })?.name
        default: return nil
        }
    }

    private var previewText: String {
        switch target {
        case .page: return draft.addSeparator && !draft.text.isEmpty ? draft.text + "\n\n*****" : draft.text
        case .newPage: return titleAndBody.body
        default: return draft.text
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if target == .baserow {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        baserowSection
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }
                .frame(maxHeight: .infinity)
            } else {
                // No outer ScrollView: PlainTextEditor already wraps its own
                // NSScrollView/UITextView, and nesting a second one capped
                // the box to its content height.
                captureBox
                    .padding(.bottom, 16)
                    .frame(maxHeight: .infinity)

                if canSave || craftErrorMessage != nil || statusMessage != nil {
                    VStack(alignment: .trailing, spacing: 8) {
                        if let craftErrorMessage {
                            Text(craftErrorMessage)
                                .foregroundStyle(.red)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if let statusMessage {
                            Text(statusMessage)
                                .foregroundStyle(Theme.secondaryText(effectiveScheme))
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if canSave {
                            PillButton(systemImage: "arrow.up.circle", label: isCraftSubmitting ? "Saving…" : "Save", action: save)
                                .disabled(isCraftSubmitting)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }

            destinationCard
        }
        .animation(.easeInOut(duration: 0.15), value: canSave)
        .foregroundStyle(Theme.primary(effectiveScheme))
        .onAppear(perform: handleOnAppear)
        .onChange(of: target) {
            craftErrorMessage = nil
            statusMessage = nil
            if target == .baserow { carryDraftTextIntoForm() }
        }
    }

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            destinationHeader
            if isDestinationExpanded {
                ScrollView {
                    destinationFields
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.sidebarCardCornerRadius, style: .continuous)
                .fill(Theme.sidebarCardBackground(effectiveScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.sidebarCardCornerRadius, style: .continuous)
                .stroke(Theme.primary(effectiveScheme).opacity(Theme.borderOpacity), lineWidth: Theme.borderWidth)
        )
        .padding(.horizontal, destinationCardHorizontalInset)
        .padding(.bottom, Theme.sidebarCardInset)
        .frame(maxHeight: isDestinationExpanded ? 340 : nil)
    }

    /// "Destination" + where it's currently pointed + a chevron. The whole
    /// bar is the button, on every platform.
    private var destinationHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isDestinationExpanded.toggle() }
        } label: {
            HStack(spacing: 10) {
                // The label never shrinks or wraps; only the description
                // after it gives way (single line, ellipsis in the middle).
                Text("Destination")
                    .font(.system(size: Theme.inputFontSize(), weight: Theme.headingWeight))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
                Spacer(minLength: 8)
                HStack(spacing: 0) {
                    Text(name(target))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if let detail = summaryDetail {
                        Text(" · " + detail)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .font(.system(size: Theme.inputFontSize()))
                .foregroundStyle(Theme.secondaryText(effectiveScheme))
                .layoutPriority(1)
                Image(systemName: isDestinationExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText(effectiveScheme))
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, isDestinationExpanded ? 0 : 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isDestinationExpanded ? "Collapse" : "Expand")
    }

    // MARK: - Capture box

    @ViewBuilder
    private var captureBox: some View {
        FieldBox(scheme: effectiveScheme, bordered: false) {
            ZStack(alignment: .topLeading) {
                if draft.text.isEmpty && !isPreviewing {
                    Text("Nothing here yet.")
                        .font(.system(size: inputFontSize))
                        .foregroundStyle(Theme.secondaryText(effectiveScheme))
                        .padding(12)
                        .allowsHitTesting(false)
                }
                // The editor stays mounted while previewing, just hidden and
                // disabled, so its cursor and scroll position survive.
                PlainTextEditor(
                    text: $draft.text, fontSize: inputFontSize, scheme: effectiveScheme, autoFocusWhen: isActive
                )
                .frame(minHeight: 120, maxHeight: .infinity)
                .opacity(isPreviewing ? 0 : 1)
                .disabled(isPreviewing)

                if isPreviewing {
                    CapturePreviewPane(
                        text: previewText,
                        title: target == .newPage ? titleAndBody.title : nil,
                        fontSize: inputFontSize, scheme: effectiveScheme
                    )
                }
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Destination fields

    @ViewBuilder
    private var destinationFields: some View {
        FieldBox(scheme: effectiveScheme) {
            MenuFieldPicker(
                placeholder: "Choose where this goes",
                options: CaptureTarget.allCases.map { (label: name($0), value: $0) },
                noneValue: CaptureTarget.page,
                selection: $draft.target, fontSize: inputFontSize, scheme: effectiveScheme
            )
        }

        switch target {
        case .page:
            pageFields
        case .newPage:
            newPageFields
        case .task:
            taskFields
        case .reflection:
            hint("Adds to today's note in Craft.")
        case .bits:
            hint("Saves a new Bit.")
        case .baserow:
            hint("Pick a database and table above; fields appear here in the form.")
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: inputFontSize))
            .foregroundStyle(Theme.secondaryText(effectiveScheme))
            .padding(.horizontal, 20)
            .padding(.top, 12)
    }

    @ViewBuilder
    private var pageFields: some View {
        FieldBox(scheme: effectiveScheme) {
            VStack(alignment: .leading, spacing: 0) {
                if let selectedDoc {
                    HStack {
                        Text(selectedDoc.title).font(.system(size: inputFontSize)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Change") {
                            self.selectedDoc = nil
                            subPages = []
                        }
                        .font(.system(.footnote))
                    }
                    .padding(12)

                    // Sub-pages of whatever's selected: Craft's `documents
                    // list` never surfaces these, only full-space `search`
                    // does, with no sense of which one you meant. So: search
                    // for the parent, then pick from what's directly inside
                    // it. One level deep.
                    if isLoadingSubPages {
                        ProgressView().padding(.horizontal, 12).padding(.bottom, 12)
                    } else if !subPages.isEmpty && selectedDoc.id == subPagesParentId {
                        Divider()
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(subPages, id: \.id) { sub in
                                Button {
                                    self.selectedDoc = CraftDocument(id: sub.id, title: sub.markdown)
                                    subPages = []
                                } label: {
                                    Text(sub.markdown)
                                        .font(.system(size: inputFontSize))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                } else {
                    TextField("Search documents…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: inputFontSize))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .padding(12)
                    if documentStore.isRefreshing && documentStore.documents.isEmpty {
                        ProgressView().padding(12)
                    } else if !results.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(results) { doc in
                                Button {
                                    selectedDoc = doc
                                    Task { await loadSubPages(of: doc) }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(doc.title).font(.system(size: inputFontSize)).lineLimit(1)
                                        if let folder = doc.folder {
                                            Text(folder)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .font(.system(size: inputFontSize))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }

        // Brandon adds a "*****" separator after nearly every Craft capture
        // by hand; this saves that step. Right-aligned to line up with Save.
        HStack {
            Spacer()
            Toggle("Add Separator", isOn: $draft.addSeparator)
                .font(.system(size: inputFontSize))
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var folderResults: [CraftFolder] {
        let q = folderQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return allFolders }
        return allFolders.filter { $0.path.lowercased().contains(q) }
    }

    @ViewBuilder
    private var newPageFields: some View {
        FieldBox(scheme: effectiveScheme) {
            VStack(alignment: .leading, spacing: 0) {
                if let selectedFolder {
                    HStack {
                        Text(selectedFolder.path).font(.system(size: inputFontSize)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Change") { self.selectedFolder = nil }
                            .font(.system(.footnote))
                    }
                    .padding(12)
                } else {
                    TextField("Search folders…", text: $folderQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: inputFontSize))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .padding(12)
                    if isLoadingFolders && allFolders.isEmpty {
                        ProgressView().padding(12)
                    } else if !folderResults.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(folderResults) { folder in
                                Button {
                                    selectedFolder = folder
                                } label: {
                                    Text(folder.path)
                                        .font(.system(size: inputFontSize))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        hint("The first line becomes the page's title.")
    }

    @ViewBuilder
    private var taskFields: some View {
        FieldLabel(title: "Due date (optional)")
        FieldBox(scheme: effectiveScheme) {
            VStack(alignment: .leading, spacing: 0) {
                Toggle("Set a due date", isOn: $includeDueDate)
                    .font(.system(size: inputFontSize))
                    .padding(12)
                if includeDueDate {
                    Divider().padding(.leading, 12)
                    DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                        .padding(12)
                }
            }
        }
        FieldLabel(title: "Inbox (optional)")
        FieldBox(scheme: effectiveScheme) {
            MenuFieldPicker(
                placeholder: "Default (\(store.config.defaultInbox?.name ?? "Craft Inbox"))",
                options: store.config.inboxes.map { (label: $0.name, value: Optional($0.id)) },
                noneValue: Optional<String>.none,
                selection: $taskInboxId, fontSize: inputFontSize, scheme: effectiveScheme
            )
        }
    }

    // MARK: - Saving

    private func save() {
        switch target {
        case .page: submitCraft()
        case .newPage: submitNewPage()
        case .reflection: sendSimple("Reflection", saveReflection)
        case .bits: sendSimple("Bits", saveBit)
        case .task: submitTask()
        case .baserow: break
        }
    }

    private func flash(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if statusMessage == message { statusMessage = nil }
        }
    }

    /// One-off destinations (Bits, Reflection, Task) snap back to the default
    /// destination afterward, so the next capture doesn't land there by
    /// accident.
    private func finishOneOff(_ message: String) {
        draft.text = ""
        flash(message)
        draft.target = defaultTarget
    }

    private func sendSimple(_ label: String, _ operation: @escaping (String) async -> String?) {
        let text = trimmedText
        isCraftSubmitting = true
        craftErrorMessage = nil
        Task {
            let failure = await operation(text)
            isCraftSubmitting = false
            if let failure {
                craftErrorMessage = failure
            } else {
                finishOneOff("Sent to \(label)")
            }
        }
    }

    private func submitTask() {
        let oneLine = trimmedText.split(whereSeparator: \.isNewline).joined(separator: " ")
        let inbox = store.config.inboxes.first { $0.id == taskInboxId } ?? store.config.defaultInbox
        let due = includeDueDate ? dueDate : nil
        isCraftSubmitting = true
        craftErrorMessage = nil
        Task {
            func finished(_ message: String) {
                isCraftSubmitting = false
                includeDueDate = false
                taskInboxId = nil
                finishOneOff(message)
            }
            do {
                if !outbox.isOnline { throw URLError(.notConnectedToInternet) }
                try await store.addTaskNow(text: oneLine, dueDate: due, destination: inbox)
                finished("Task added")
            } catch {
                if isClearlyOffline(error) {
                    outbox.enqueue(OutboxItem(kind: .task, text: oneLine,
                                              dueDay: due.map { TaskStore.isoDay($0) }, inboxId: inbox?.id))
                    finished("Offline: task will be added when you're back online")
                } else {
                    isCraftSubmitting = false
                    craftErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func loadFolders() {
        guard !isLoadingFolders, store.config.isConfigured else { return }
        isLoadingFolders = true
        Task {
            defer { isLoadingFolders = false }
            let client = CraftClient(url: store.config.craftLink)
            guard let folders = try? await client.listFolders() else { return }
            allFolders = folders
        }
    }

    private func submitNewPage() {
        guard let selectedFolder else { return }
        let (title, body) = titleAndBody
        isCraftSubmitting = true
        craftErrorMessage = nil
        let client = CraftClient(url: store.config.craftLink)
        let folderId = selectedFolder.id
        Task {
            do {
                if !outbox.isOnline && pendingPage == nil { throw URLError(.notConnectedToInternet) }
                // Reuse a page left over from an earlier attempt whose body
                // append failed, rather than creating an empty duplicate.
                let newId: String
                if let pending = pendingPage, pending.title == title, pending.folderId == folderId {
                    newId = pending.id
                } else {
                    newId = try await client.createDocument(title: title, folderId: folderId)
                    pendingPage = (newId, title, folderId)
                }
                if !body.isEmpty {
                    try await client.appendBlocks(pageId: newId, markdown: body)
                }
                pendingPage = nil
                draft.text = ""
                isCraftSubmitting = false
                flash("Created “\(title)”")
            } catch {
                if isClearlyOffline(error) {
                    // Queue it, resuming from the page if it was already created.
                    outbox.enqueue(OutboxItem(kind: .newPage, text: body, title: title, folderId: folderId,
                                              createdPageId: pendingPage?.id))
                    pendingPage = nil
                    draft.text = ""
                    isCraftSubmitting = false
                    flash("Offline: “\(title)” will be created when you're back online")
                } else {
                    craftErrorMessage = error.localizedDescription
                    isCraftSubmitting = false
                }
            }
        }
    }

    /// Fields the capture box's text can go into.
    private var captureCandidates: [BaserowField] {
        fields.filter { $0.type == "long_text" || $0.type == "text" }
    }

    /// The remembered field for this table, else the first long-text (then
    /// single-line text) field that isn't a comments field — "My Comments"
    /// on the Seneca table is rarely where a quote belongs.
    private var captureField: BaserowField? {
        let candidates = captureCandidates
        if let tableId, let id = store.config.baserowCaptureFields[String(tableId)],
           let remembered = candidates.first(where: { $0.id == id }) { return remembered }
        func isComment(_ f: BaserowField) -> Bool { f.name.localizedCaseInsensitiveContains("comment") }
        return candidates.first { $0.type == "long_text" && !isComment($0) }
            ?? candidates.first { !isComment($0) }
            ?? candidates.first
    }

    private var captureFieldBinding: Binding<Int> {
        Binding(
            get: { captureField?.id ?? -1 },
            set: { newId in
                guard let tableId, let new = captureCandidates.first(where: { $0.id == newId }) else { return }
                // Move the text: take it out of the old field (if it's still
                // exactly what we put there) and into the new one.
                if let old = captureField, old.id != newId, textValues[old.id] == draft.text {
                    textValues[old.id] = nil
                }
                store.config.baserowCaptureFields[String(tableId)] = newId
                store.config.save()
                if !trimmedText.isEmpty { textValues[new.id] = draft.text }
            }
        )
    }

    /// Typed text follows you into Baserow: it lands in the table's capture
    /// field (see `captureField`) when that's still empty, and is cleared
    /// from the capture box once the row is pushed.
    private func carryDraftTextIntoForm() {
        guard !trimmedText.isEmpty, let field = captureField,
              (textValues[field.id] ?? "").isEmpty else { return }
        textValues[field.id] = draft.text
    }

    private func submitCraft() {
        guard let selectedDoc else { return }
        isCraftSubmitting = true
        craftErrorMessage = nil
        let client = CraftClient(url: store.config.craftLink)
        // Blank line before the ***** — not appended directly onto the
        // last line — so Craft's markdown parser reads it as its own
        // separator block rather than folding it into the capture's last
        // paragraph/list item. Five asterisks, not three: verified live
        // against Craft that "***" round-trips to lineStyle "extraLight",
        // not "regular" — see the QuickCapture ghost-text comment history
        // (removed above) for the full verification.
        let markdown = draft.addSeparator ? draft.text + "\n\n*****" : draft.text
        Task {
            do {
                if !outbox.isOnline { throw URLError(.notConnectedToInternet) }
                try await client.appendBlocks(pageId: selectedDoc.id, markdown: markdown)
                // Mark the top-level parent used, not the sub-page itself,
                // when one was selected — Brandon: sub-page titles repeat
                // across parents (many docs have their own "1:1s"), so
                // showing one bare in the recents list would be ambiguous
                // about which one it actually was. Top-level titles are
                // unique enough to be unambiguous, so that's what recents
                // shows; the sub-page pick still lands in the right place
                // in Craft, this only affects which entry gets bumped here.
                let idToMarkUsed = subPagesParentId ?? selectedDoc.id
                documentStore.markUsed(idToMarkUsed)
                isCraftSubmitting = false
                // The page stays selected so repeat captures to it are just
                // type + Save; the collapsed bar always shows where it goes.
                draft.text = ""
                flash("Added to \(selectedDoc.title)")
            } catch {
                if isClearlyOffline(error) {
                    // No connection: keep it on disk and clear the screen as
                    // if sent; the outbox delivers it when we're back online.
                    outbox.enqueue(OutboxItem(kind: .craftPage, text: markdown,
                                              pageId: selectedDoc.id, pageTitle: selectedDoc.title))
                    documentStore.markUsed(subPagesParentId ?? selectedDoc.id)
                    isCraftSubmitting = false
                    draft.text = ""
                    flash("Offline: will send to \(selectedDoc.title) when you're back online")
                } else {
                    craftErrorMessage = error.localizedDescription
                    isCraftSubmitting = false
                }
            }
        }
    }

    private func loadSubPages(of doc: CraftDocument) async {
        subPages = []
        subPagesParentId = doc.id
        isLoadingSubPages = true
        defer { isLoadingSubPages = false }
        let client = CraftClient(url: store.config.craftLink)
        subPages = (try? await client.subPages(of: doc.id)) ?? []
    }

    // MARK: - Baserow section (formerly BaserowCaptureView)

    @ViewBuilder
    private var baserowSection: some View {
        if store.config.baserowDatabases.isEmpty {
            Text("No databases configured. Open Settings to add one.")
                .font(.system(size: inputFontSize))
                .foregroundStyle(Theme.secondaryText(effectiveScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
        } else {
            FieldLabel(title: "Database")
            FieldBox(scheme: effectiveScheme) {
                MenuFieldPicker(
                    placeholder: "Select a database",
                    options: store.config.baserowDatabases.map { (label: $0.name, value: Optional($0.id)) },
                    noneValue: Optional<Int>.none,
                    selection: $databaseId, fontSize: inputFontSize, scheme: effectiveScheme
                )
            }
            .onChange(of: databaseId) {
                Task { await loadTables(for: databaseId) }
            }

            FieldLabel(title: "Table")
            FieldBox(scheme: effectiveScheme) {
                if isLoadingTables {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(12)
                } else {
                    MenuFieldPicker(
                        placeholder: tables.isEmpty ? "Select a database first" : "Select a table",
                        options: tables.map { (label: $0.name, value: Optional($0.id)) },
                        noneValue: Optional<Int>.none,
                        selection: $tableId, fontSize: inputFontSize, scheme: effectiveScheme,
                        disabled: tables.isEmpty
                    )
                }
            }
            .onChange(of: tableId) {
                Task { await loadFields(for: tableId) }
            }

            if isLoadingFields {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.top, 20)
            } else if !fields.isEmpty {
                // Only when there's text to place and a real choice to make.
                if !trimmedText.isEmpty && captureCandidates.count > 1 {
                    FieldLabel(title: "Your typed text goes in")
                    FieldBox(scheme: effectiveScheme) {
                        MenuFieldPicker(
                            placeholder: "Choose a field",
                            options: captureCandidates.map { (label: $0.name, value: $0.id) },
                            noneValue: -1,
                            selection: captureFieldBinding, fontSize: inputFontSize, scheme: effectiveScheme
                        )
                    }
                }
                ForEach(fields) { field in
                    fieldInput(for: field)
                }
            }

            if let baserowErrorMessage {
                HStack(alignment: .firstTextBaseline) {
                    Text(baserowErrorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                    Spacer()
                    if let loadFailure {
                        Button("Retry") {
                            Task {
                                switch loadFailure {
                                case .tables: await loadTables(for: databaseId)
                                case .fields: await loadFields(for: tableId)
                                }
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }

            if tableId != nil && !fields.isEmpty {
                HStack {
                    Spacer()
                    PillButton(systemImage: "arrow.up.circle", label: isBaserowSubmitting ? "Pushing…" : "Push") {
                        Task { await submitBaserow() }
                    }
                    .disabled(isBaserowSubmitting)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
    }

    @ViewBuilder
    private func fieldInput(for field: BaserowField) -> some View {
        switch field.type {
        case "boolean":
            FieldBox(scheme: effectiveScheme) {
                Toggle(field.name, isOn: boolBinding(field.id))
                    .font(.system(size: inputFontSize))
                    .padding(12)
            }

        case "long_text":
            FieldLabel(title: field.name)
            FieldBox(scheme: effectiveScheme) {
                PlainTextEditor(text: textBinding(field.id), fontSize: inputFontSize, scheme: effectiveScheme)
                    .frame(minHeight: 80)
            }

        case "single_select":
            FieldLabel(title: field.name)
            FieldBox(scheme: effectiveScheme) {
                MenuFieldPicker(
                    placeholder: "— none —",
                    options: (field.selectOptions ?? []).map { (label: $0.value, value: $0.value) },
                    noneValue: "",
                    selection: textBinding(field.id), fontSize: inputFontSize, scheme: effectiveScheme
                )
            }

        case "multiple_select":
            FieldLabel(title: field.name)
            FieldBox(scheme: effectiveScheme) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(field.selectOptions ?? [], id: \.value) { opt in
                        Toggle(opt.value, isOn: multiSelectBinding(field.id, opt.value))
                            .font(.system(size: inputFontSize))
                    }
                }
                .padding(12)
            }

        case "date":
            FieldLabel(title: field.name)
            FieldBox(scheme: effectiveScheme) {
                VStack(alignment: .leading, spacing: 0) {
                    Toggle("Set \(field.name.lowercased())", isOn: dateIncludeBinding(field.id))
                        .font(.system(size: inputFontSize))
                        .padding(12)
                    if includeDateFields.contains(field.id) {
                        Divider().padding(.leading, 12)
                        DatePicker(
                            field.name, selection: dateBinding(field.id),
                            displayedComponents: field.dateIncludeTime == true ? [.date, .hourAndMinute] : [.date]
                        )
                        .padding(12)
                    }
                }
            }

        case "number", "rating":
            FieldLabel(title: field.name)
            FieldBox(scheme: effectiveScheme) {
                TextField("", text: textBinding(field.id))
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .font(.system(size: inputFontSize))
                    .padding(12)
            }

        default:
            FieldLabel(title: field.name)
            FieldBox(scheme: effectiveScheme) {
                TextField("", text: textBinding(field.id))
                    #if os(iOS)
                    .textInputAutocapitalization(field.type == "email" ? .never : .sentences)
                    .keyboardType(field.type == "email" ? .emailAddress : (field.type == "url" ? .URL : .default))
                    #endif
                    .font(.system(size: inputFontSize))
                    .padding(12)
            }
        }
    }

    // MARK: - Baserow bindings

    private func textBinding(_ id: Int) -> Binding<String> {
        Binding(get: { textValues[id] ?? "" }, set: { textValues[id] = $0 })
    }

    private func boolBinding(_ id: Int) -> Binding<Bool> {
        Binding(get: { boolValues[id] ?? false }, set: { boolValues[id] = $0 })
    }

    private func dateBinding(_ id: Int) -> Binding<Date> {
        Binding(get: { dateValues[id] ?? Date() }, set: { dateValues[id] = $0 })
    }

    private func dateIncludeBinding(_ id: Int) -> Binding<Bool> {
        Binding(
            get: { includeDateFields.contains(id) },
            set: { newValue in
                if newValue {
                    includeDateFields.insert(id)
                    if dateValues[id] == nil { dateValues[id] = Date() }
                } else {
                    includeDateFields.remove(id)
                }
            }
        )
    }

    private func multiSelectBinding(_ id: Int, _ option: String) -> Binding<Bool> {
        Binding(
            get: { multiSelectValues[id]?.contains(option) ?? false },
            set: { newValue in
                var set = multiSelectValues[id] ?? []
                if newValue { set.insert(option) } else { set.remove(option) }
                multiSelectValues[id] = set
            }
        )
    }

    // MARK: - Baserow loading

    /// Shows the last-known table list immediately (if there is one) and
    /// refreshes it behind the scenes, so picking a database is instant after
    /// the first time. Only a first-ever load shows a spinner, and only that
    /// can fail visibly — a failed refresh behind a cached list is silent.
    private func loadTables(for databaseId: Int?) async {
        tables = []
        tableId = nil
        guard let databaseId else { return }
        loadFailure = nil
        let cached = await BaserowCache.shared.tables(for: databaseId)
        if let cached {
            tables = cached
            chooseDefaultTable()
        } else {
            isLoadingTables = true
        }
        defer { isLoadingTables = false }
        do {
            let fresh = try await baserowClient.listTables(databaseId: databaseId)
            guard databaseId == self.databaseId else { return } // picked another database meanwhile
            if fresh != tables {
                tables = fresh
                if let current = tableId, !fresh.contains(where: { $0.id == current }) { tableId = nil }
            }
            chooseDefaultTable()
            baserowErrorMessage = nil
        } catch {
            guard databaseId == self.databaseId, cached == nil else { return }
            baserowErrorMessage = error.localizedDescription
            loadFailure = .tables
        }
    }

    /// Only picks when nothing is selected: the database's single table, else
    /// the last-used one, else "All" (nearly every database has one).
    private func chooseDefaultTable() {
        guard tableId == nil else { return }
        if tables.count == 1 {
            tableId = tables[0].id
        } else if let lastTable = store.config.lastBaserowTableId, tables.contains(where: { $0.id == lastTable }) {
            tableId = lastTable
        } else if let all = tables.first(where: { $0.name.caseInsensitiveCompare("All") == .orderedSame }) {
            tableId = all.id
        }
    }

    /// Same cached-first approach as loadTables. A refresh that finds the
    /// form's shape unchanged does nothing; one that finds it changed swaps
    /// the fields in without wiping what's already typed.
    private func loadFields(for tableId: Int?) async {
        fields = []
        clearFieldValues()
        guard let tableId else { return }
        loadFailure = nil
        let cached = await BaserowCache.shared.fields(for: tableId)
        if let cached {
            fields = formFields(from: cached)
            applyFieldDefaults()
        } else {
            isLoadingFields = true
        }
        defer { isLoadingFields = false }
        do {
            let fresh = formFields(from: try await baserowClient.listFields(tableId: tableId))
            guard tableId == self.tableId else { return } // picked another table meanwhile
            if fresh != fields {
                fields = fresh
                applyFieldDefaults()
            }
            baserowErrorMessage = nil
        } catch {
            guard tableId == self.tableId, cached == nil else { return }
            baserowErrorMessage = error.localizedDescription
            loadFailure = .fields
        }
    }

    /// "Archived" specifically excluded, on top of the isWritable filter —
    /// Brandon: it's Baserow bookkeeping he doesn't want showing up (or
    /// accidentally set) in the Quick Capture form, across any table that
    /// happens to have a field by that name.
    private func formFields(from all: [BaserowField]) -> [BaserowField] {
        all.filter { $0.isWritable && $0.name.caseInsensitiveCompare("Archived") != .orderedSame }
    }

    private func clearFieldValues() {
        textValues = [:]
        boolValues = [:]
        multiSelectValues = [:]
        dateValues = [:]
        includeDateFields = []
    }

    /// Captures made here are tagged as coming from Arthur: any table with a
    /// "Source" single-select that has an "Arthur" option (e.g. Quinn) gets it
    /// preselected, and again after each push clears the form.
    private func applyFieldDefaults() {
        for field in fields where field.type == "single_select"
            && field.name.caseInsensitiveCompare("Source") == .orderedSame {
            if let arthur = field.selectOptions?.first(where: { $0.value.caseInsensitiveCompare("Arthur") == .orderedSame }) {
                // Only when nothing's chosen yet, so a refresh can't undo a
                // Source the user already changed.
                if textValues[field.id] == nil { textValues[field.id] = arthur.value }
            }
        }
        if target == .baserow { carryDraftTextIntoForm() }
    }

    // MARK: - Baserow submit

    private func submitBaserow() async {
        guard let tableId else { return }
        isBaserowSubmitting = true
        baserowErrorMessage = nil
        defer { isBaserowSubmitting = false }

        var payload: [String: Any] = [:]
        for field in fields {
            switch field.type {
            case "boolean":
                payload[field.name] = boolValues[field.id] ?? false
            case "number", "rating":
                if let raw = textValues[field.id], let num = Double(raw) {
                    payload[field.name] = num
                }
            case "date":
                if includeDateFields.contains(field.id), let date = dateValues[field.id] {
                    if field.dateIncludeTime == true {
                        payload[field.name] = ISO8601DateFormatter().string(from: date)
                    } else {
                        payload[field.name] = Self.dateOnlyFormatter.string(from: date)
                    }
                }
            case "multiple_select":
                if let set = multiSelectValues[field.id], !set.isEmpty {
                    payload[field.name] = Array(set)
                }
            default:
                if let raw = textValues[field.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                    payload[field.name] = raw
                }
            }
        }

        do {
            // Remember whether the capture box's text rode along into the
            // form, so it can be cleared once it has actually been sent.
            let carried = captureField
                .flatMap { textValues[$0.id] }?.trimmingCharacters(in: .whitespacesAndNewlines)
            var queued = false
            do {
                if !outbox.isOnline { throw URLError(.notConnectedToInternet) }
                try await baserowClient.createRow(tableId: tableId, fields: payload)
            } catch {
                guard isClearlyOffline(error), let json = try? JSONSerialization.data(withJSONObject: payload) else {
                    throw error
                }
                let summary = payload.values.compactMap { $0 as? String }.joined(separator: " · ")
                outbox.enqueue(OutboxItem(kind: .baserow, text: summary.isEmpty ? "Baserow row" : summary,
                                          tableId: tableId, fieldsJSON: json))
                queued = true
            }
            if let carried, carried == trimmedText { draft.text = "" }
            store.config.lastBaserowDatabaseId = databaseId
            store.config.lastBaserowTableId = tableId
            store.config.save()
            clearFieldValues()
            applyFieldDefaults()
            if queued { baserowErrorMessage = "Offline: saved, will push when you're back online." }
        } catch {
            baserowErrorMessage = error.localizedDescription
        }
    }
}

/// Stand-in for SwiftUI's `Picker` in the Baserow form (Database, Table,
/// single_select fields). A plain `Picker` outside a List ignores an
/// explicit `.font()` for its own displayed selected-value button — it
/// always renders in the system's own accent-blue control font/weight
/// regardless of what we set `inputFontSize` to, which is what made
/// "Bits"/"Brandon" read noticeably bigger than every other row in Quick
/// Capture on iOS (Brandon: "fonts... are much larger"). Not visible on
/// Mac — AppKit's Picker equivalent doesn't have this quirk. Building the
/// label ourselves via `Menu` gives full control over font/color so it
/// matches the surrounding Text exactly, on every platform.
struct MenuFieldPicker<Value: Hashable>: View {
    let placeholder: String
    let options: [(label: String, value: Value)]
    let noneValue: Value
    @Binding var selection: Value
    let fontSize: CGFloat
    let scheme: ColorScheme
    var disabled: Bool = false

    private var currentLabel: String {
        options.first(where: { $0.value == selection })?.label ?? placeholder
    }

    var body: some View {
        Menu {
            Button(placeholder) { selection = noneValue }
            ForEach(options, id: \.value) { opt in
                Button(opt.label) { selection = opt.value }
            }
        } label: {
            HStack {
                Text(currentLabel)
                    .font(.system(size: fontSize))
                    .foregroundStyle(Theme.primary(scheme))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: fontSize * 0.65, weight: .medium))
                    .foregroundStyle(Theme.secondaryText(scheme))
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
