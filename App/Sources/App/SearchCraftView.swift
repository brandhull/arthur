import SwiftUI
import ArthurKit

/// Natural-language Q&A over Craft content — not a browse-and-pick tool like
/// Quick Capture's document search. Brandon's example: "What's the Pacific
/// building code?" should surface "12345" directly, not just point at the
/// document it's buried in. Agentic retrieval: Claude drives its own lookup
/// via tools (search_craft/list_subpages/read_document, all backed by
/// CraftClient — see AnthropicClient.answer) instead of this view
/// pre-guessing a fixed set of candidate documents and handing Claude
/// whatever that guess picked. Deliberately not a full embeddings/semantic-
/// search system — see the design discussion this followed: with Brandon's
/// content volume and near-daily growth, an indexing pipeline's upkeep cost
/// wasn't worth it over Claude doing targeted, bounded tool calls instead.
///
/// Layout mirrors Quick Capture's Baserow section exactly, per Brandon's
/// explicit spec: "Search" sits where "Database" does, the search field
/// matches the database picker's position/dimensions, and the answer
/// appears below with no bordering container — just the text itself.
struct SearchCraftView: View {
    @ObservedObject var store: TaskStore
    @Environment(\.colorScheme) private var systemScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var query = ""
    @State private var isSearching = false
    @State private var answer: String?
    @State private var sourceTitle: String?
    @State private var sourceId: String?
    @State private var errorMessage: String?

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FieldLabel(title: "Search")
                FieldBox(scheme: effectiveScheme) {
                    TextField("Ask a question about your Craft space…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: inputFontSize))
                        #if os(iOS)
                        .textInputAutocapitalization(.sentences)
                        #endif
                        .padding(12)
                        .onSubmit(performSearch)
                }

                if isSearching {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(.top, 20)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                } else if let answer {
                    // No FieldBox/border here — Brandon's explicit ask: just
                    // the answer text, flowing directly below the search
                    // field, matching how read-only content flows
                    // everywhere else in the app now (Rocks/Tasks/
                    // Reflection's unbordered ContentBox).
                    Text(answer)
                        .font(.system(size: inputFontSize))
                        .foregroundStyle(Theme.primary(effectiveScheme))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    if let sourceTitle {
                        Button {
                            Task { await openSource() }
                        } label: {
                            Text("From: \(sourceTitle)")
                                .font(.system(.footnote))
                                .foregroundStyle(Theme.secondaryText(effectiveScheme))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .foregroundStyle(Theme.primary(effectiveScheme))
    }

    private func performSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        guard store.config.isConfigured else {
            errorMessage = CraftError.notConfigured.localizedDescription
            return
        }
        guard store.config.isAnthropicConfigured else {
            errorMessage = AnthropicError.notConfigured.localizedDescription
            return
        }
        isSearching = true
        answer = nil
        sourceTitle = nil
        sourceId = nil
        errorMessage = nil
        let craft = CraftClient(url: store.config.craftLink)
        Task {
            do {
                // Claude drives its own retrieval now (search_craft/
                // list_subpages/read_document, all backed by `craft`) rather
                // than answering from a fixed pre-guessed set of candidate
                // documents — see AnthropicClient.answer's doc comment for
                // why that fixed-guess approach was replaced.
                let anthropic = AnthropicClient(apiKey: store.config.anthropicApiKey)
                let result = try await anthropic.answer(question: q, craft: craft)
                // Claude's own final answer already says so in plain text
                // when it genuinely couldn't find anything (per the system
                // prompt) — this is just a defensive fallback for the
                // degenerate case of a truly empty response.
                if result.answer.isEmpty {
                    errorMessage = "Nothing in Craft matched that."
                } else {
                    answer = result.answer
                    sourceTitle = result.sourceTitle
                    sourceId = result.sourceId
                }
                isSearching = false
            } catch {
                errorMessage = error.localizedDescription
                isSearching = false
            }
        }
    }

    private func openSource() async {
        guard let sourceId else { return }
        let craft = CraftClient(url: store.config.craftLink)
        guard let link = try? await craft.clickableLink(forBlockId: sourceId), let url = URL(string: link) else { return }
        #if os(iOS)
        await UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
}
