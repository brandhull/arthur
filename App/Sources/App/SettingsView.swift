import SwiftUI
import ArthurKit

/// Built with FieldBox/FieldLabel rather than native Form — matches the
/// app-wide 8pt corner radius (ContentBox/PillButton/Tasks List) instead of
/// native Form's grouped-section rounding. The two explicit exceptions,
/// left as native controls: the Appearance segmented picker (System/Light/
/// Dark) and the Task filter pill (not on this screen at all). The Inbox
/// documents list stays a real List (not FieldBox) so drag-to-reorder and
/// swipe-to-delete keep working — those depend on List's own machinery —
/// but its background is hidden and redrawn at the same 8pt radius so it
/// still matches everything else visually.
struct SettingsView: View {
    @ObservedObject var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemScheme

    @State private var craftLink: String = ""
    @State private var appearance: AppearanceMode = .system

    // Live, not store.config — reflects the Picker selection below as you
    // change it, so switching Light/Dark previews immediately in this
    // window's own background rather than waiting for Done to be tapped.
    private var effectiveScheme: ColorScheme {
        Theme.effectiveScheme(appearance: appearance, system: systemScheme)
    }
    @State private var inboxes: [InboxDestination] = []
    @State private var defaultInboxId: String?
    @State private var newInboxName = ""
    @State private var newInboxURL = ""
    @State private var isResolving = false
    @State private var resolveError: String?
    @State private var isSyncing = false

    // Temporary debug aid — see the comment where debugLogURL's row is
    // built, and CraftClient.logParseFailure/logTaskAddTrace in ArthurKit.
    // Two separate files: the generic one is any call() SSE-parse miss
    // (Quick Capture, Rocks, or a task add's own steps); the trace one is
    // task-add specific, showing both the append and update legs together.
    @State private var hasDebugLog = false
    @State private var hasTaskTraceLog = false
    private var debugLogURL: URL {
        Config.supportDir.appendingPathComponent("craft_debug_last_failure.txt")
    }
    private var taskTraceLogURL: URL {
        Config.supportDir.appendingPathComponent("craft_debug_task_trace.txt")
    }

    @State private var baserowToken: String = ""
    @State private var baserowDatabases: [BaserowDatabase] = []
    @State private var newBaserowName = ""
    @State private var newBaserowId = ""
    @State private var baserowAddError: String?

    @State private var senecaDatabaseId: Int?
    @State private var senecaTableId: Int?
    @State private var senecaTables: [BaserowTable] = []
    @State private var isLoadingSenecaTables = false
    @State private var senecaQuoteField: String = "Quote"
    @State private var senecaAuthorField: String = "Author"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FieldLabel(title: "Craft connection")
                    FieldBox(scheme: effectiveScheme) {
                        TextField("", text: $craftLink)
                            .multilineTextAlignment(.leading)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .padding(12)
                    }

                    FieldLabel(title: "Inbox documents")
                    if !inboxes.isEmpty {
                        List {
                            ForEach(inboxes) { inbox in
                                HStack {
                                    Text(inbox.name)
                                    #if os(macOS)
                                    // macOS Lists have no swipe-to-delete
                                    // gesture, and .onDelete only fires via
                                    // a selected row + the Delete key — this
                                    // List has no selection binding, so
                                    // nothing was ever deletable here.
                                    // iOS/iPadOS already have swipe (via
                                    // EditButton) and don't need this.
                                    Spacer()
                                    Button {
                                        inboxes.removeAll { $0.id == inbox.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    #endif
                                }
                                .listRowBackground(Color.clear)
                            }
                            .onDelete { indexSet in
                                inboxes.remove(atOffsets: indexSet)
                            }
                            .onMove { indices, newOffset in
                                inboxes.move(fromOffsets: indices, toOffset: newOffset)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .frame(height: CGFloat(inboxes.count) * 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Theme.primary(effectiveScheme).opacity(Theme.borderOpacity), lineWidth: Theme.borderWidth)
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    }

                    FieldBox(scheme: effectiveScheme) {
                        VStack(alignment: .leading, spacing: 0) {
                            TextField("Name (e.g. Personal)", text: $newInboxName)
                                .multilineTextAlignment(.leading)
                                .padding(12)
                            Divider().padding(.leading, 12)
                            TextField("Craft document URL", text: $newInboxURL)
                                .multilineTextAlignment(.leading)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .autocorrectionDisabled()
                                .padding(12)
                        }
                    }
                    .padding(.bottom, 8)

                    Button {
                        Task { await resolveAndAddInbox() }
                    } label: {
                        HStack {
                            Spacer()
                            if isResolving {
                                ProgressView()
                            } else {
                                Text("Add inbox document")
                            }
                            Spacer()
                        }
                        .padding(12)
                    }
                    .buttonStyle(.plain)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.primary(effectiveScheme).opacity(Theme.borderOpacity), lineWidth: Theme.borderWidth)
                    )
                    .padding(.horizontal, 20)
                    .disabled(newInboxName.isEmpty || newInboxURL.isEmpty || craftLink.isEmpty || isResolving)

                    if let resolveError {
                        Text(resolveError)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }

                    if !inboxes.isEmpty {
                        FieldLabel(title: "Default inbox")
                        FieldBox(scheme: effectiveScheme) {
                            Picker("Default", selection: $defaultInboxId) {
                                Text("Craft Inbox (standard)").tag(String?.none)
                                ForEach(inboxes) { inbox in
                                    Text(inbox.name).tag(String?.some(inbox.id))
                                }
                            }
                            .padding(12)
                        }
                    }

                    FieldLabel(title: "Baserow connection")
                    FieldBox(scheme: effectiveScheme) {
                        TextField("API token", text: $baserowToken)
                            .multilineTextAlignment(.leading)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .padding(12)
                    }

                    FieldLabel(title: "Baserow databases")
                    // Baserow's database-token auth can't list a workspace's
                    // databases (that endpoint is JWT-only), so — same as
                    // the Chrome extension — these are hand-entered once
                    // here; tables and fields underneath each one are still
                    // fetched live.
                    if !baserowDatabases.isEmpty {
                        List {
                            ForEach(baserowDatabases) { db in
                                HStack {
                                    Text(db.name)
                                    Spacer()
                                    // String(db.id), not Text("\(db.id)") —
                                    // interpolating an Int directly into a
                                    // Text applies locale number formatting
                                    // (1,234 style grouping), which turns a
                                    // Baserow database ID into something that
                                    // looks like a different number entirely.
                                    Text(String(db.id))
                                        .foregroundStyle(Theme.secondaryText(effectiveScheme))
                                    #if os(macOS)
                                    // Same reason as the Inbox documents
                                    // list above — macOS has no swipe
                                    // gesture and this List has no selection
                                    // binding, so .onDelete alone was
                                    // unreachable.
                                    Button {
                                        baserowDatabases.removeAll { $0.id == db.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    #endif
                                }
                                .listRowBackground(Color.clear)
                            }
                            .onDelete { indexSet in
                                baserowDatabases.remove(atOffsets: indexSet)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .frame(height: CGFloat(baserowDatabases.count) * 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Theme.primary(effectiveScheme).opacity(Theme.borderOpacity), lineWidth: Theme.borderWidth)
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    }

                    FieldBox(scheme: effectiveScheme) {
                        VStack(alignment: .leading, spacing: 0) {
                            TextField("Name (e.g. Captures)", text: $newBaserowName)
                                .multilineTextAlignment(.leading)
                                .padding(12)
                            Divider().padding(.leading, 12)
                            TextField("Database ID (number)", text: $newBaserowId)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .multilineTextAlignment(.leading)
                                .padding(12)
                        }
                    }
                    .padding(.bottom, 8)

                    Button {
                        addBaserowDatabase()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Add database")
                            Spacer()
                        }
                        .padding(12)
                    }
                    .buttonStyle(.plain)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.primary(effectiveScheme).opacity(Theme.borderOpacity), lineWidth: Theme.borderWidth)
                    )
                    .padding(.horizontal, 20)
                    .disabled(newBaserowName.isEmpty || newBaserowId.isEmpty)

                    if let baserowAddError {
                        Text(baserowAddError)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }

                    FieldLabel(title: "Seneca (commonplace book)")
                    // Same Database → Table cascade as the Baserow tab
                    // itself — Seneca is just a specific table Arthur reads
                    // from for the splash screen, configured once here
                    // rather than re-picked every launch.
                    FieldBox(scheme: effectiveScheme) {
                        Picker("Database", selection: $senecaDatabaseId) {
                            Text("Select a database").tag(Int?.none)
                            ForEach(baserowDatabases) { db in
                                Text(db.name).tag(Int?.some(db.id))
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: senecaDatabaseId) {
                        Task { await loadSenecaTables(for: senecaDatabaseId) }
                    }

                    FieldBox(scheme: effectiveScheme) {
                        if isLoadingSenecaTables {
                            HStack { Spacer(); ProgressView(); Spacer() }.padding(12)
                        } else {
                            Picker("Table", selection: $senecaTableId) {
                                Text(senecaTables.isEmpty ? "Select a database first" : "Select a table").tag(Int?.none)
                                ForEach(senecaTables) { t in
                                    Text(t.name).tag(Int?.some(t.id))
                                }
                            }
                            .padding(12)
                            .disabled(senecaTables.isEmpty)
                        }
                    }
                    .padding(.top, 8)

                    FieldBox(scheme: effectiveScheme) {
                        VStack(alignment: .leading, spacing: 0) {
                            TextField("Quote field name", text: $senecaQuoteField)
                                .multilineTextAlignment(.leading)
                                .padding(12)
                            Divider().padding(.leading, 12)
                            TextField("Author field name (optional)", text: $senecaAuthorField)
                                .multilineTextAlignment(.leading)
                                .padding(12)
                        }
                    }
                    .padding(.top, 8)

                    // Not user-configurable, unlike Quote/Author above —
                    // Arthur writes to this field itself (to bias which
                    // quote shows next), Brandon never reads it, so there's
                    // nothing for a text field here to let him rename.
                    Text("Add a Date field named \"Last shown\" to this table so Arthur can avoid repeating quotes too soon — optional, but without it every refill is a plain shuffle.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText(effectiveScheme))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // Appearance segmented control — left native, per
                    // Brandon's explicit exception (along with the Task
                    // filter pill elsewhere) from the roundedness cleanup.
                    FieldLabel(title: "Appearance")
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag(AppearanceMode.system)
                        Text("Light").tag(AppearanceMode.light)
                        Text("Dark").tag(AppearanceMode.dark)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)

                    FieldLabel(title: "Sync")
                    Button {
                        Task {
                            isSyncing = true
                            await store.forceSync()
                            isSyncing = false
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isSyncing {
                                ProgressView()
                            } else {
                                Text("Force Sync")
                            }
                            Spacer()
                        }
                        .padding(12)
                    }
                    .buttonStyle(.plain)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.primary(effectiveScheme).opacity(Theme.borderOpacity), lineWidth: Theme.borderWidth)
                    )
                    .padding(.horizontal, 20)
                    .disabled(isSyncing || craftLink.isEmpty)

                    // Temporary — only appears after a real "Unexpected
                    // response from Craft" failure, since CraftClient
                    // writes to this exact path right before throwing that
                    // error (see logParseFailure). Brandon's reports of
                    // that error only ever describe *symptoms* on the Mac
                    // side ("it reached Craft, right place, right date"),
                    // since Mac's shared config dir made earlier debugging
                    // possible there — this button exists because iOS has
                    // no equivalent easy access to a sandboxed app's
                    // container without Xcode's device browser. ShareLink
                    // (not a clipboard copy) so it works identically on Mac
                    // and iOS, and so the file itself — not just its text —
                    // reaches me however Brandon chooses to send it.
                    if hasDebugLog {
                        FieldLabel(title: "Debug")
                        ShareLink(item: debugLogURL) {
                            HStack {
                                Spacer()
                                Text("Share Craft Debug Log")
                                Spacer()
                            }
                            .padding(12)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Theme.primary(effectiveScheme).opacity(Theme.borderOpacity), lineWidth: Theme.borderWidth)
                        )
                        .padding(.horizontal, 20)
                    }
                    if hasTaskTraceLog {
                        ShareLink(item: taskTraceLogURL) {
                            HStack {
                                Spacer()
                                Text("Share Task-Add Trace")
                                Spacer()
                            }
                            .padding(12)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Theme.primary(effectiveScheme).opacity(Theme.borderOpacity), lineWidth: Theme.borderWidth)
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, hasDebugLog ? 8 : 0)
                    }
                }
                .padding(.bottom, 16)
            }
            .foregroundStyle(Theme.primary(effectiveScheme))
            .background(Theme.background(effectiveScheme))
            .navigationTitle("Settings")
            .toolbar {
                #if os(iOS)
                // macOS Lists support drag-to-reorder directly; iOS needs
                // Edit mode active before its drag handles appear.
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                }
            }
            .onAppear(perform: loadFromStore)
        }
        .preferredColorScheme(appearance == .system ? nil : effectiveScheme)
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 480, idealHeight: 560)
        #endif
    }

    private func loadFromStore() {
        hasDebugLog = FileManager.default.fileExists(atPath: debugLogURL.path)
        hasTaskTraceLog = FileManager.default.fileExists(atPath: taskTraceLogURL.path)
        craftLink = store.config.craftLink
        appearance = store.config.appearance
        inboxes = store.config.inboxes
        defaultInboxId = store.config.defaultInboxId
        baserowToken = store.config.baserowToken
        baserowDatabases = store.config.baserowDatabases
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        senecaDatabaseId = store.config.senecaDatabaseId
        senecaTableId = store.config.senecaTableId
        senecaQuoteField = store.config.senecaQuoteField
        senecaAuthorField = store.config.senecaAuthorField
        // Setting senecaDatabaseId above (nil -> a real id) fires the
        // .onChange handler on the Picker, which loads this database's
        // tables — no separate call needed here.
    }

    private func loadSenecaTables(for databaseId: Int?) async {
        guard let databaseId else {
            senecaTables = []
            return
        }
        isLoadingSenecaTables = true
        defer { isLoadingSenecaTables = false }
        let client = BaserowClient(token: baserowToken)
        let tables = (try? await client.listTables(databaseId: databaseId)) ?? []
        senecaTables = tables
        // Only clear the selection if it doesn't belong to this database's
        // tables — preserves the restored senecaTableId from loadFromStore
        // (set just before this runs) rather than wiping it out.
        if let senecaTableId, !tables.contains(where: { $0.id == senecaTableId }) {
            self.senecaTableId = nil
        }
    }

    private func addBaserowDatabase() {
        baserowAddError = nil
        guard let id = Int(newBaserowId.trimmingCharacters(in: .whitespaces)) else {
            baserowAddError = "Database ID must be a number — find it in the Baserow URL (e.g. /database/494108/)."
            return
        }
        baserowDatabases.append(BaserowDatabase(id: id, name: newBaserowName))
        baserowDatabases.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        newBaserowName = ""
        newBaserowId = ""
    }

    private func resolveAndAddInbox() async {
        isResolving = true
        resolveError = nil
        defer { isResolving = false }
        do {
            let client = CraftClient(url: craftLink)
            let id = try await client.resolveLink(newInboxURL)
            inboxes.append(InboxDestination(id: id, name: newInboxName, url: newInboxURL))
            // Deliberately NOT auto-setting this as the default — an unset
            // default means Craft's standard inbox, which is where Brandon
            // wants Personal/Leapcure tasks to keep landing even after
            // Business/BYUI/Church docs exist.
            newInboxName = ""
            newInboxURL = ""
        } catch {
            resolveError = error.localizedDescription
        }
    }

    private func save() {
        // If the default inbox was deleted from the list above, don't persist
        // a defaultInboxId pointing at a destination that no longer exists —
        // nil correctly falls back to Craft's standard inbox.
        if let id = defaultInboxId, !inboxes.contains(where: { $0.id == id }) {
            defaultInboxId = nil
        }
        store.config.craftLink = craftLink
        store.config.appearance = appearance
        store.config.inboxes = inboxes
        store.config.defaultInboxId = defaultInboxId
        store.config.baserowToken = baserowToken
        // If the last-used database was deleted from the list above, clear
        // the remembered selection so BaserowCaptureView doesn't try to load
        // tables for a database that no longer exists.
        if let lastId = store.config.lastBaserowDatabaseId, !baserowDatabases.contains(where: { $0.id == lastId }) {
            store.config.lastBaserowDatabaseId = nil
            store.config.lastBaserowTableId = nil
        }
        store.config.baserowDatabases = baserowDatabases
        // Same guard as lastBaserowDatabaseId above — if the database
        // Seneca pointed at was deleted from the list, drop the now-stale
        // table selection too rather than leaving it dangling.
        if let dbId = senecaDatabaseId, !baserowDatabases.contains(where: { $0.id == dbId }) {
            senecaDatabaseId = nil
            senecaTableId = nil
        }
        store.config.senecaDatabaseId = senecaDatabaseId
        store.config.senecaTableId = senecaTableId
        store.config.senecaQuoteField = senecaQuoteField.trimmingCharacters(in: .whitespaces).isEmpty ? "Quote" : senecaQuoteField
        store.config.senecaAuthorField = senecaAuthorField.trimmingCharacters(in: .whitespaces).isEmpty ? "Author" : senecaAuthorField
        store.config.save()
        store.reloadConfig()
        Task { await store.forceSync() }
    }
}
