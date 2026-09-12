import SwiftUI
import ArthurKit

/// The "Document" quick-add flow — 99% the same screen as Quick Capture's
/// Craft mode (capture box + collapsible Destination card), but the
/// Destination card searches Craft *folders* instead of existing documents,
/// and submitting creates a brand-new page inside the chosen folder
/// (CraftClient.createDocument) rather than appending markdown to one that
/// already exists. Not part of the sidebar/drawer nav yet — Brandon's
/// explicit ask was "for now" only reachable via the quick-add popup's
/// "Document" row.
///
/// Embedded as a fifth opacity-swapped layer in AgendaView's tabContent,
/// the same pattern as Rocks/Tasks/Quick Capture/Reflection — not a sheet
/// or full-window cover. Two earlier attempts got this wrong in opposite
/// directions: a small popup card (didn't read as "full window" like Quick
/// Capture), then a true full-window overlay/fullScreenCover (covered the
/// sidebar/hamburger menu too, which Brandon still needed reachable). This
/// is what actually gives "looks like Quick Capture's screen, sidebar and
/// all" — MacAgendaLayout/iOSAgendaLayout's own chrome already wraps
/// tabContent, so embedding here inherits it for free.
///
/// No "Add Separator" toggle here — that only makes sense when appending
/// onto existing content, which this never does. The new page's title is
/// the capture box's first line, trimmed and excluded from the body pushed
/// below it (so it doesn't appear twice — once as Craft's own page title,
/// once as a body line) — matching Brandon's ask that this screen "look
/// exactly the same" as Quick Capture's, i.e. no separate Title field.
struct DocumentCaptureSheet: View {
    @ObservedObject var store: TaskStore
    // Not part of a real presentation (no sheet/fullScreenCover here to
    // supply @Environment(\.dismiss)) — the X button closes this the same
    // way picking a different sidebar destination does, by flipping the
    // same showingDocumentCapture flag AgendaView's tabContent already
    // keys this view's visibility on.
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var systemScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var text = ""
    @State private var query = ""
    @State private var selectedFolder: CraftFolder?
    @State private var allFolders: [CraftFolder] = []
    @State private var isLoadingFolders = false
    @State private var isDestinationExpanded = false
    @State private var isSubmitting = false
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

    private var destinationCardHorizontalInset: CGFloat {
        #if os(macOS)
        return Theme.sidebarCardInset
        #else
        return 16
        #endif
    }

    private var results: [CraftFolder] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return allFolders }
        return allFolders.filter { $0.name.lowercased().contains(q) }
    }

    /// First non-empty line becomes the new page's title; everything after
    /// it (including any blank line right after the title) is the body
    /// pushed into the page once it exists.
    private var titleAndBody: (title: String, body: String) {
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let title = lines.first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        let body = lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .newlines) : ""
        return (title, body)
    }

    private var isSubmitDisabled: Bool {
        titleAndBody.title.isEmpty || selectedFolder == nil || isSubmitting
    }

    private func handleOnAppear() {
        guard allFolders.isEmpty, !isLoadingFolders else { return }
        isLoadingFolders = true
        Task {
            defer { isLoadingFolders = false }
            let client = CraftClient(url: store.config.craftLink)
            allFolders = (try? await client.listFolders())?.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            } ?? []
        }
    }

    private func submit() {
        guard let selectedFolder else { return }
        let (title, body) = titleAndBody
        isSubmitting = true
        let client = CraftClient(url: store.config.craftLink)
        Task {
            do {
                let newId = try await client.createDocument(title: title, folderId: selectedFolder.id)
                if !body.isEmpty {
                    try await client.appendBlocks(pageId: newId, markdown: body)
                }
                text = ""
                query = ""
                self.selectedFolder = nil
                isSubmitting = false
                isPresented = false
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            captureBox
                .padding(.bottom, 16)
                .frame(maxHeight: .infinity)

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
            .frame(maxHeight: isDestinationExpanded ? 280 : nil)
        }
        .foregroundStyle(Theme.primary(effectiveScheme))
        .background(Theme.background(effectiveScheme))
        .overlay(alignment: .topTrailing) {
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText(effectiveScheme))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            .padding(.trailing, 6)
        }
        .onAppear(perform: handleOnAppear)
    }

    private var destinationHeader: some View {
        HStack {
            #if os(macOS)
            Text("Destination")
                .font(.system(size: 15, weight: Theme.headingWeight))
                .foregroundStyle(Color.primary)
            #else
            Text("Destination")
                .font(.system(size: Theme.inputFontSize(), weight: Theme.headingWeight))
                .foregroundStyle(Color.primary)
            #endif
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isDestinationExpanded.toggle() }
            } label: {
                Image(systemName: isDestinationExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText(effectiveScheme))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isDestinationExpanded ? "Collapse" : "Expand")
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, isDestinationExpanded ? 0 : 14)
    }

    @ViewBuilder
    private var captureBox: some View {
        FieldBox(scheme: effectiveScheme, bordered: false) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Nothing here yet.")
                        .font(.system(size: inputFontSize))
                        .foregroundStyle(Theme.secondaryText(effectiveScheme))
                        .padding(12)
                        .allowsHitTesting(false)
                }
                PlainTextEditor(text: $text, fontSize: inputFontSize, scheme: effectiveScheme)
                    .frame(minHeight: 120, maxHeight: .infinity)
            }
        }
        .padding(.top, 36)
    }

    @ViewBuilder
    private var destinationFields: some View {
        FieldBox(scheme: effectiveScheme) {
            VStack(alignment: .leading, spacing: 0) {
                if let selectedFolder {
                    HStack {
                        Text(selectedFolder.name).font(.system(size: inputFontSize))
                        Spacer()
                        Button("Change") { self.selectedFolder = nil }
                            .font(.system(.footnote))
                    }
                    .padding(12)
                } else {
                    TextField("Search folders…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: inputFontSize))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .padding(12)
                    if isLoadingFolders {
                        ProgressView().padding(12)
                    } else if !results.isEmpty {
                        Divider()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(results) { folder in
                                    Button {
                                        selectedFolder = folder
                                    } label: {
                                        Text(folder.name)
                                            .font(.system(size: inputFontSize))
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

        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
                .font(.caption)
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }

        HStack {
            Spacer()
            PillButton(systemImage: "arrow.up.circle", label: isSubmitting ? "Saving…" : "Save", action: submit)
                .disabled(isSubmitDisabled)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}
