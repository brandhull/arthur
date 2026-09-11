import SwiftUI
import ArthurKit

/// Menu-bar sibling of the main app's Quick Capture Craft box — free text to
/// any Craft document/sub-page, same destination search and "Add Separator"
/// behavior, trimmed down for a small floating panel (no ghost-text cheat
/// sheet, no Baserow side — Brandon's ask was specifically "I just want to
/// quick capture something," not the full Quick Capture tab). Shares
/// ArthurKit's DocumentStore with the main app, so its recents/cache are the
/// exact same file on disk — using this popup keeps the main app's Quick
/// Capture suggestions in sync, and vice versa.
///
/// Destination starts collapsed (same as the main app's Quick Capture card)
/// so the text editor gets the bulk of the panel's height — "more room to
/// type," per Brandon's ask — and only the 3 most-recently-used matches show
/// once it's expanded, rather than every match at once.
struct QuickCaptureBarView: View {
    let onSubmit: () -> Void

    @StateObject private var documentStore = DocumentStore()
    @State private var config = Config.load()
    @State private var text = ""
    @State private var query = ""
    @State private var selectedDoc: CraftDocument?
    @State private var subPages: [CraftClient.CraftBlock] = []
    @State private var subPagesParentId: String?
    @State private var isLoadingSubPages = false
    @State private var isDestinationExpanded = false
    @State private var addSeparator = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    // limit: 3, not the default 8 — Brandon: too many matches/recents
    // showing at once in this small panel; caps both the empty-query
    // recents list and typed-search results the same way.
    private var results: [CraftDocument] { documentStore.search(query, limit: 3) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Capture").font(.headline)

            BarTextEditor(text: $text, font: .systemFont(ofSize: 13))
                // Uniform 6pt inset on every side — without it the cursor/
                // text sat flush against the box's edges with no breathing
                // room (Brandon: "cursor was oddly placed"), since a plain
                // TextEditor has no built-in content inset of its own to
                // separate it from the border drawn right at its bounds.
                .padding(6)
                .frame(minHeight: 160, maxHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))

            destinationHeader
            if isDestinationExpanded {
                destinationFields
            }

            HStack {
                Spacer()
                Toggle("Add Separator", isOn: $addSeparator)
                    .toggleStyle(.checkbox)
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Save", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || selectedDoc == nil || isSubmitting)
            }
        }
        .padding()
        // Reports this view's actual (variable) height to the hosting
        // NSPanel — see AppDelegate's showQuickCapturePanel — so the panel
        // grows/shrinks as Destination expands/collapses instead of staying
        // pinned to one fixed size.
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 340)
        // Always dark — Brandon's explicit ask, no setting to change it.
        // ArthurBar never had an appearance toggle of its own; this
        // overrides whatever the system/main-app appearance happens to be.
        .preferredColorScheme(.dark)
        .onAppear {
            config = Config.load()
            documentStore.refreshIfStale(craftLink: config.craftLink)
        }
    }

    /// "Destination" title + collapse/expand chevron — same disclosure
    /// affordance as the main app's Quick Capture card.
    private var destinationHeader: some View {
        Button {
            isDestinationExpanded.toggle()
        } label: {
            HStack {
                Text("Destination").font(.subheadline)
                Spacer()
                Image(systemName: isDestinationExpanded ? "chevron.down" : "chevron.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var destinationFields: some View {
        if let selectedDoc {
            HStack {
                Text(selectedDoc.title).font(.subheadline)
                Spacer()
                Button("Change") {
                    self.selectedDoc = nil
                    subPages = []
                }
                .font(.caption)
            }
            if isLoadingSubPages {
                ProgressView().controlSize(.small)
            } else if !subPages.isEmpty && selectedDoc.id == subPagesParentId {
                ForEach(subPages, id: \.id) { sub in
                    Button {
                        self.selectedDoc = CraftDocument(id: sub.id, title: sub.markdown)
                        subPages = []
                    } label: {
                        Text(sub.markdown)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else {
            TextField("Search documents…", text: $query)
                .textFieldStyle(.roundedBorder)
            if !results.isEmpty {
                ForEach(results) { doc in
                    Button {
                        selectedDoc = doc
                        Task { await loadSubPages(of: doc) }
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(doc.title).font(.subheadline)
                            if let folder = doc.folder {
                                Text(folder).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loadSubPages(of doc: CraftDocument) async {
        subPages = []
        subPagesParentId = doc.id
        isLoadingSubPages = true
        defer { isLoadingSubPages = false }
        let client = CraftClient(url: config.craftLink)
        subPages = (try? await client.subPages(of: doc.id)) ?? []
    }

    private func submit() {
        guard let selectedDoc else { return }
        guard !config.craftLink.isEmpty else {
            errorMessage = "Set your Craft link in Arthur's Settings first."
            return
        }
        isSubmitting = true
        let client = CraftClient(url: config.craftLink)
        // Same separator markdown as the main app's Quick Capture — verified
        // live that ***** (not ***) is what actually round-trips to Craft's
        // "regular" separator style.
        let markdown = addSeparator ? text + "\n\n*****" : text
        Task {
            do {
                try await client.appendBlocks(pageId: selectedDoc.id, markdown: markdown)
                // Marks the top-level parent used, not the sub-page itself,
                // when one was picked — same fix as the main app's Quick
                // Capture, for the same reason (sub-page titles like "1:1s"
                // repeat across parents and would be ambiguous in recents).
                documentStore.markUsed(subPagesParentId ?? selectedDoc.id)
                text = ""
                query = ""
                self.selectedDoc = nil
                subPages = []
                addSeparator = true
                isSubmitting = false
                onSubmit()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
