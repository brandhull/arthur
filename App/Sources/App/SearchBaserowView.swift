import SwiftUI
import ArthurKit

/// Search Baserow tab — visually built by duplicating Quick Capture's shape
/// per Brandon's explicit instruction: the same header row (now two
/// DropdownButtons instead of the Craft/Baserow pill toggle), the same
/// search-field-then-submit-button pattern as the Craft section (just
/// shorter, to leave room for the Search button), and an invisible-border
/// ContentBox standing in for "Destination" as the results container.
///
/// There's no cross-table search in Baserow's API — narrowing to one
/// specific table via the Table dropdown (Brandon's choice, over searching
/// every table in a database at once) means each search is a single
/// `listRows(tableId:search:)` call, not a fan-out across tables.
struct SearchBaserowView: View {
    @ObservedObject var store: TaskStore
    @Environment(\.colorScheme) private var systemScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var selectedDatabase: BaserowDatabase?
    @State private var selectedTable: BaserowTable?
    @State private var tables: [BaserowTable] = []
    @State private var isLoadingTables = false

    @State private var query = ""
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var results: [BaserowRow] = []
    @State private var resultFields: [BaserowField] = []
    @State private var errorMessage: String?
    @State private var selectedResult: BaserowRow?

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

    /// Matches the nav dropdown's own font size, not just its height —
    /// Brandon asked for these to be its visual sibling ("same dimensions
    /// as the navigation dropdown"), and AgendaView.tabDropdown's label is
    /// system font at tabFontSize, so this mirrors that exactly rather than
    /// just borrowing the box shape.
    private var dropdownFontSize: CGFloat {
        #if os(iOS)
        return horizontalSizeClass == .regular ? Theme.sectionHeadingSize : 12
        #else
        return Theme.sectionHeadingSize
        #endif
    }

    private var dropdownHeight: CGFloat {
        #if os(iOS)
        return Theme.controlHeight(horizontalSizeClass: horizontalSizeClass)
        #else
        return Theme.controlHeight()
        #endif
    }

    private var sortedDatabases: [BaserowDatabase] {
        store.config.baserowDatabases.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var sortedTables: [BaserowTable] {
        tables.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var baserowClient: BaserowClient {
        BaserowClient(token: store.config.baserowToken)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    DropdownButton(
                        items: sortedDatabases, label: { $0.name }, selection: $selectedDatabase,
                        placeholder: "Database", scheme: effectiveScheme,
                        font: .system(size: dropdownFontSize, weight: Theme.headingWeight), height: dropdownHeight
                    )
                    DropdownButton(
                        items: sortedTables, label: { $0.name }, selection: $selectedTable,
                        placeholder: selectedDatabase == nil ? "Select database" : "Table",
                        scheme: effectiveScheme,
                        font: .system(size: dropdownFontSize, weight: Theme.headingWeight), height: dropdownHeight,
                        disabled: selectedDatabase == nil || isLoadingTables
                    )
                }
                .padding(.horizontal, 20)
                .frame(height: Theme.headerRowHeight)
                .foregroundStyle(Theme.primary(effectiveScheme))

                // Same shape as Quick Capture's Capture box, just shorter
                // (60 vs 120) — Brandon: shrink it to make room for a
                // dedicated Search button below, rather than searching as
                // you type.
                FieldBox(scheme: effectiveScheme) {
                    ZStack(alignment: .topLeading) {
                        if query.isEmpty {
                            Text("Search…")
                                .font(.system(size: inputFontSize))
                                .foregroundStyle(Theme.secondaryText(effectiveScheme))
                                .padding(12)
                                .allowsHitTesting(false)
                        }
                        PlainTextEditor(text: $query, fontSize: inputFontSize, scheme: effectiveScheme)
                            .frame(minHeight: 60)
                    }
                }
                .padding(.top, 16)

                HStack {
                    Spacer()
                    // Same PillButton, same dimensions, as Quick Capture's
                    // Save button.
                    PillButton(systemImage: "magnifyingglass", label: isSearching ? "Searching…" : "Search") {
                        Task { await runSearch() }
                    }
                    // Query is no longer required to enable this — an empty
                    // query with a table selected is a real, useful case
                    // (Brandon: show the 5 most recent entries instead of
                    // just sitting there disabled), handled in runSearch().
                    .disabled(selectedTable == nil || isSearching)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                // ContentBox's exact shape/margins, bordered: false —
                // "invisible border, not gray" per Brandon. Stands in for
                // Craft's "Destination" box/label; results appear here.
                ContentBox(scheme: effectiveScheme, bordered: false) {
                    if isSearching {
                        HStack { Spacer(); ProgressView(); Spacer() }.padding(12)
                    } else if results.isEmpty {
                        Text(hasSearched ? "No matches." : "Nothing here yet.")
                            .font(.system(size: inputFontSize))
                            .foregroundStyle(Theme.secondaryText(effectiveScheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, row in
                                Button {
                                    selectedResult = row
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(primaryValue(for: row))
                                            .font(.system(size: inputFontSize, weight: .medium))
                                        if let snippet = snippetValue(for: row) {
                                            Text(snippet)
                                                .font(.system(size: inputFontSize))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                if index < results.count - 1 {
                                    Divider().padding(.leading, 12)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 16)
            }
            .padding(.bottom, 16)
        }
        .foregroundStyle(Theme.primary(effectiveScheme))
        .onChange(of: selectedDatabase) {
            Task { await loadTables() }
        }
        .onChange(of: selectedTable) {
            results = []
            hasSearched = false
            resultFields = []
            // Field metadata belongs to the table, not the search — moved
            // here from runSearch(), which was refetching it on every
            // single Search click even when the table hadn't changed since
            // the last one. A table's fields don't change between two
            // searches in the same session.
            Task { await loadFields() }
        }
        .sheet(item: $selectedResult) { row in
            BaserowRowDetailView(row: row, fields: resultFields, scheme: effectiveScheme)
        }
    }

    private func loadTables() async {
        tables = []
        selectedTable = nil
        guard let selectedDatabase else { return }
        isLoadingTables = true
        defer { isLoadingTables = false }
        do {
            tables = try await baserowClient.listTables(databaseId: selectedDatabase.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadFields() async {
        guard let selectedTable else { return }
        do {
            resultFields = try await baserowClient.listFields(tableId: selectedTable.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runSearch() async {
        guard let selectedTable else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = true
        hasSearched = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            if trimmed.isEmpty {
                // No query — Brandon: show the 5 most recent entries rather
                // than requiring a query to see anything at all.
                //
                // Not `orderBy: "-id"` — confirmed live that Baserow
                // rejects ordering by the synthetic "id" column when
                // `user_field_names=true` is set ("ERROR_ORDER_BY_FIELD_NOT_FOUND"),
                // and there's no field guaranteed to exist on every table
                // to order by instead. Default (unordered) row order
                // tracks creation order unless a row's been manually
                // dragged to a new position in Baserow's own UI, so this
                // fetches in that default order and takes the tail client-
                // side instead of asking the API to sort.
                let all = try await baserowClient.listRows(tableId: selectedTable.id)
                results = Array(all.suffix(5).reversed())
            } else {
                results = try await baserowClient.listRows(tableId: selectedTable.id, search: trimmed)
            }
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
    }

    // MARK: - Result row display

    private func primaryValue(for row: BaserowRow) -> String {
        if let primaryField = resultFields.first(where: { $0.primary }),
           let value = Self.displayString(row.fields[primaryField.name]) {
            return value
        }
        return "Untitled"
    }

    private func snippetValue(for row: BaserowRow) -> String? {
        for field in resultFields where !field.primary {
            if let value = Self.displayString(row.fields[field.name]), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Baserow's *read* response shape for select/link fields differs from
    /// the flat strings `createRow` sends on write — a single_select value
    /// comes back as `{"value": "...", ...}`, multiple_select/
    /// link_to_table as an array of those objects. This unwraps any of
    /// those generically instead of a per-type switch (like fieldInput's,
    /// built for editable *input*) since read-only display doesn't need to
    /// distinguish field types the way building an input for one does.
    /// Shared with BaserowRowDetailView so both the result list and the
    /// detail popup format values identically.
    static func displayString(_ raw: Any?) -> String? {
        guard let raw, !(raw is NSNull) else { return nil }
        if let dict = raw as? [String: Any] {
            return dict["value"] as? String
        }
        if let array = raw as? [[String: Any]] {
            let values = array.compactMap { $0["value"] as? String }
            return values.isEmpty ? nil : values.joined(separator: ", ")
        }
        if let array = raw as? [Any] {
            let values = array.map { "\($0)" }
            return values.isEmpty ? nil : values.joined(separator: ", ")
        }
        if let bool = raw as? Bool {
            return bool ? "Yes" : "No"
        }
        if let string = raw as? String {
            return string.isEmpty ? nil : string
        }
        return "\(raw)"
    }
}
