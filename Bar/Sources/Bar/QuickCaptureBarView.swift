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
    @State private var addSeparator = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var results: [CraftDocument] { documentStore.search(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Capture").font(.headline)

            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(minHeight: 80, maxHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))

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

            Toggle("Add Separator", isOn: $addSeparator)
                .toggleStyle(.checkbox)

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
        .frame(width: 340)
        .onAppear {
            config = Config.load()
            documentStore.refreshIfStale(craftLink: config.craftLink)
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
