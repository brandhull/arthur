import SwiftUI
import ArthurKit

enum QuickCaptureSource: String, CaseIterable, Identifiable, Hashable {
    case craft = "Craft"
    case baserow = "Baserow"
    var id: String { rawValue }
}

/// Combines the two former standalone tabs — free-form text pushed to any
/// Craft page, and a row pushed into any configured Baserow table — behind
/// one Craft/Baserow toggle, per Brandon's request. The toggle uses
/// PillFilterBar, the same component (not just the same look) as the Tasks
/// filter, at the same position in the header row.
struct QuickCaptureView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var documentStore: DocumentStore
    @EnvironmentObject var draft: QuickCaptureDraft
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @Environment(\.colorScheme) private var systemScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var source: QuickCaptureSource = .craft

    // MARK: Craft state
    // craftText/addSeparator used to be local @State here — now they live
    // on the shared `draft` (QuickCaptureDraft) instead, so the Mac-only
    // pop-out window (QuickCapturePopoutView) shows/edits the exact same
    // in-progress text rather than a copy that has to be synced.
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
    @State private var skippedFieldNames: [String] = []
    @State private var textValues: [Int: String] = [:]
    @State private var boolValues: [Int: Bool] = [:]
    @State private var multiSelectValues: [Int: Set<String>] = [:]
    @State private var dateValues: [Int: Date] = [:]
    @State private var includeDateFields: Set<Int> = []
    @State private var isLoadingTables = false
    @State private var isLoadingFields = false
    @State private var isBaserowSubmitting = false
    @State private var baserowErrorMessage: String?

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    private var results: [CraftDocument] { documentStore.search(query) }

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

    /// Matches Tasks' own filterFontSize exactly — same reasoning (Mac
    /// flagged as too small at the smaller size, iOS/iPadOS weren't).
    private var filterFontSize: CGFloat {
        #if os(macOS)
        return 14
        #else
        return 13
        #endif
    }

    private var baserowClient: BaserowClient {
        BaserowClient(token: store.config.baserowToken)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    PillFilterBar(
                        items: QuickCaptureSource.allCases, label: { $0.rawValue },
                        selection: $source, scheme: effectiveScheme, fontSize: filterFontSize
                    )
                    Spacer()
                    #if os(macOS)
                    // Same row as the Craft/Baserow filter, not overlaid on
                    // the capture box itself — Brandon: overlaid on the box
                    // it clipped against the box's own rounded border.
                    // Craft-only, since the pop-out has nothing to do with
                    // a Baserow row.
                    if source == .craft {
                        Button {
                            openWindow(id: "quickCapturePopout")
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.secondaryText(effectiveScheme))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Open in a separate window")
                    }
                    #endif
                }
                .padding(.horizontal, 20)
                .frame(height: Theme.headerRowHeight)
                .foregroundStyle(Theme.primary(effectiveScheme))

                if source == .craft {
                    craftSection
                } else {
                    baserowSection
                }
            }
            .padding(.bottom, 16)
        }
        .foregroundStyle(Theme.primary(effectiveScheme))
        .onAppear {
            documentStore.refreshIfStale(craftLink: store.config.craftLink)
            if databaseId == nil, let lastDb = store.config.lastBaserowDatabaseId,
               store.config.baserowDatabases.contains(where: { $0.id == lastDb }) {
                databaseId = lastDb
            }
        }
    }

    // MARK: - Craft section (formerly CaptureSheet)

    @ViewBuilder
    private var craftSection: some View {
        FieldBox(scheme: effectiveScheme) {
            ZStack(alignment: .topLeading) {
                if draft.text.isEmpty {
                    // A quick-reference cheat sheet for the markdown syntax
                    // Craft itself understands, not just a generic
                    // placeholder — Brandon: this is specifically to help
                    // him learn/use markdown better while typing a capture,
                    // since whatever's typed here goes straight through to
                    // Craft as real markdown (see appendBlocks/CraftClient),
                    // unlike Baserow's plain-text long_text field. Scoped to
                    // just this box, not every "Nothing here yet." placeholder
                    // in the app — Rocks/Reflection's empty states aren't
                    // input fields, and this list is explicitly kept short
                    // (Brandon's own request) rather than exhaustive.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nothing here yet.")
                        // Blank line between the placeholder and the
                        // reference list — an empty Text, not extra
                        // .padding, so it takes up exactly one line's
                        // height at this same font size rather than an
                        // arbitrary point value.
                        Text(verbatim: "")
                        // Text(verbatim:), not the default Text(_:) — that
                        // initializer treats a string literal as
                        // LocalizedStringKey and auto-parses its own inline
                        // markdown, so "**Strong**" rendered as an actual
                        // bold "Strong" and the link syntax rendered as a
                        // real styled link — exactly backwards from showing
                        // the raw syntax as an example. verbatim forces it
                        // to display literally instead.
                        // "##", not "#" — a Craft doc's own title already
                        // renders as H1, so a capture landing inside it
                        // should default to H2 as the example, not compete
                        // with the page title's own size.
                        Text(verbatim: "## Heading")
                        Text(verbatim: "**Strong**")
                        Text(verbatim: "- [ ] Todo")
                        Text(verbatim: "- Bullet")
                        // No space between ] and ( — a space there breaks
                        // the link syntax.
                        Text(verbatim: "[link text](URL)")
                    }
                    .font(.system(size: inputFontSize))
                    .foregroundStyle(Theme.secondaryText(effectiveScheme))
                    .padding(12)
                    .allowsHitTesting(false)
                }
                PlainTextEditor(text: $draft.text, fontSize: inputFontSize, scheme: effectiveScheme)
                    .frame(minHeight: 120)
            }
        }
        .padding(.top, 16)

        // Bumped from 4 — Brandon: it read as too close to the Capture box
        // above it.
        FieldLabel(title: "Destination", topPadding: 10)

        FieldBox(scheme: effectiveScheme) {
            VStack(alignment: .leading, spacing: 0) {
                if let selectedDoc {
                    HStack {
                        Text(selectedDoc.title).font(.system(size: inputFontSize))
                        Spacer()
                        Button("Change") {
                            self.selectedDoc = nil
                            subPages = []
                        }
                        .font(.system(.footnote))
                    }
                    .padding(12)

                    // Sub-pages of whatever's selected — Craft's own
                    // `documents list` never surfaces these (confirmed
                    // live: a known sub-page title returned nothing from
                    // it), only full-space `search` does, and that finds
                    // sub-pages anywhere, with no sense of which one you
                    // meant. Brandon's call: search for the parent by name
                    // like today, then pick from what's directly inside it
                    // — "99 times out of 100 I will know the parent page."
                    // Hidden once a sub-page's been chosen (selectedDoc no
                    // longer matches subPagesParentId) — one level deep,
                    // not a recursive drill-down.
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
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(results) { doc in
                                    Button {
                                        selectedDoc = doc
                                        Task { await loadSubPages(of: doc) }
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(doc.title).font(.system(size: inputFontSize))
                                            if let folder = doc.folder {
                                                Text(folder)
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
        }

        // Craft-only — Baserow rows have no markdown/separator concept.
        // Brandon adds a "*****" (regular-style) separator after nearly
        // every Craft capture by hand, specifically for readability on the
        // Departmental Meetings/1:1s sub-pages — this saves that manual
        // step, on by default since that's his common case.
        Toggle("Add Separator", isOn: $draft.addSeparator)
            .font(.system(size: inputFontSize))
            .padding(.horizontal, 20)
            .padding(.top, 12)

        if let craftErrorMessage {
            Text(craftErrorMessage)
                .foregroundStyle(.red)
                .font(.caption)
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }

        HStack {
            Spacer()
            // "Save", not "Push" — Brandon's explicit rename for this
            // button specifically (Baserow's own button below keeps
            // "Push"/"Pushing…", not asked to change).
            PillButton(systemImage: "arrow.up.circle", label: isCraftSubmitting ? "Saving…" : "Save") {
                submitCraft()
            }
            .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || selectedDoc == nil || isCraftSubmitting)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func submitCraft() {
        guard let selectedDoc else { return }
        isCraftSubmitting = true
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
                try await client.appendBlocks(pageId: selectedDoc.id, markdown: markdown)
                documentStore.markUsed(selectedDoc.id)
                isCraftSubmitting = false
                draft.text = ""
                query = ""
                self.selectedDoc = nil
                subPages = []
                draft.addSeparator = true
            } catch {
                craftErrorMessage = error.localizedDescription
                isCraftSubmitting = false
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
                Picker("Database", selection: $databaseId) {
                    Text("Select a database").tag(Int?.none)
                    ForEach(store.config.baserowDatabases) { db in
                        Text(db.name).tag(Int?.some(db.id))
                    }
                }
                .padding(12)
            }
            .onChange(of: databaseId) {
                Task { await loadTables(for: databaseId) }
            }

            FieldLabel(title: "Table")
            FieldBox(scheme: effectiveScheme) {
                if isLoadingTables {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(12)
                } else {
                    Picker("Table", selection: $tableId) {
                        Text(tables.isEmpty ? "Select a database first" : "Select a table").tag(Int?.none)
                        ForEach(tables) { t in
                            Text(t.name).tag(Int?.some(t.id))
                        }
                    }
                    .padding(12)
                    .disabled(tables.isEmpty)
                }
            }
            .onChange(of: tableId) {
                Task { await loadFields(for: tableId) }
            }

            if isLoadingFields {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.top, 20)
            } else if !fields.isEmpty {
                ForEach(fields) { field in
                    fieldInput(for: field)
                }

                if !skippedFieldNames.isEmpty {
                    Text("Skipped (unsupported): \(skippedFieldNames.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText(effectiveScheme))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
            }

            if let baserowErrorMessage {
                Text(baserowErrorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
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
                Picker(field.name, selection: textBinding(field.id)) {
                    Text("— none —").tag("")
                    ForEach(field.selectOptions ?? [], id: \.value) { opt in
                        Text(opt.value).tag(opt.value)
                    }
                }
                .padding(12)
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

    private func loadTables(for databaseId: Int?) async {
        tables = []
        tableId = nil
        guard let databaseId else { return }
        isLoadingTables = true
        defer { isLoadingTables = false }
        do {
            tables = try await baserowClient.listTables(databaseId: databaseId)
            baserowErrorMessage = nil
            if let lastTable = store.config.lastBaserowTableId, tables.contains(where: { $0.id == lastTable }) {
                tableId = lastTable
            }
        } catch {
            baserowErrorMessage = error.localizedDescription
        }
    }

    private func loadFields(for tableId: Int?) async {
        fields = []
        skippedFieldNames = []
        clearFieldValues()
        guard let tableId else { return }
        isLoadingFields = true
        defer { isLoadingFields = false }
        do {
            let all = try await baserowClient.listFields(tableId: tableId)
            fields = all.filter { $0.isWritable }
            skippedFieldNames = all.filter { !$0.isWritable }.map { $0.name }
            baserowErrorMessage = nil
        } catch {
            baserowErrorMessage = error.localizedDescription
        }
    }

    private func clearFieldValues() {
        textValues = [:]
        boolValues = [:]
        multiSelectValues = [:]
        dateValues = [:]
        includeDateFields = []
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
            try await baserowClient.createRow(tableId: tableId, fields: payload)
            store.config.lastBaserowDatabaseId = databaseId
            store.config.lastBaserowTableId = tableId
            store.config.save()
            clearFieldValues()
        } catch {
            baserowErrorMessage = error.localizedDescription
        }
    }
}
