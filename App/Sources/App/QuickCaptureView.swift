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
    @Environment(\.colorScheme) private var systemScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var source: QuickCaptureSource = .craft

    // MARK: Craft state
    @State private var craftText = ""
    @State private var query = ""
    @State private var selectedDoc: CraftDocument?
    @State private var isCraftSubmitting = false
    @State private var craftErrorMessage: String?

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
                if craftText.isEmpty {
                    Text("Nothing here yet.")
                        .font(.system(size: inputFontSize))
                        .foregroundStyle(Theme.secondaryText(effectiveScheme))
                        .padding(12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $craftText)
                    .font(.system(size: inputFontSize))
                    .scrollContentBackground(.hidden)
                            .background(Color.clear) // macOS TextEditor keeps its own NSTextView background even with scrollContentBackground(.hidden) — this forces it transparent so FieldBox's own fill actually shows through, instead of a generic system gray that ignored Navy/Charcoal entirely.
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .padding(.trailing, 12)
                    .padding(.leading, 7)
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
                        Button("Change") { self.selectedDoc = nil }
                            .font(.system(.footnote))
                    }
                    .padding(12)
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
            .disabled(craftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || selectedDoc == nil || isCraftSubmitting)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func submitCraft() {
        guard let selectedDoc else { return }
        isCraftSubmitting = true
        let client = CraftClient(url: store.config.craftLink)
        Task {
            do {
                try await client.appendBlocks(pageId: selectedDoc.id, markdown: craftText)
                documentStore.markUsed(selectedDoc.id)
                isCraftSubmitting = false
                craftText = ""
                query = ""
                self.selectedDoc = nil
            } catch {
                craftErrorMessage = error.localizedDescription
                isCraftSubmitting = false
            }
        }
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
                TextEditor(text: textBinding(field.id))
                    .font(.system(size: inputFontSize))
                    .scrollContentBackground(.hidden)
                            .background(Color.clear) // macOS TextEditor keeps its own NSTextView background even with scrollContentBackground(.hidden) — this forces it transparent so FieldBox's own fill actually shows through, instead of a generic system gray that ignored Navy/Charcoal entirely.
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .padding(.trailing, 12)
                    .padding(.leading, 7)
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
