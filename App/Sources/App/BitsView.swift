import SwiftUI
import ArthurKit

private enum BitsMode: String, CaseIterable, Identifiable {
    case bits = "Bits"
    case archive = "Archive"
    var id: String { rawValue }
}

/// Bits tab — the same Baserow-backed list as the standalone Bits app:
/// newest first as bordered cards, each with Edit / Copy / Archive / Delete,
/// plus an Archive view of everything marked archived (Copy / Restore /
/// Delete there). Tapping a card's text edits it in place.
struct BitsView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var bits: BitsStore
    /// True while this tab is the selected one — reloads the list on arrival
    /// so Bits added elsewhere (the Bits app, another device) show up.
    let isActive: Bool
    @Environment(\.colorScheme) private var systemScheme

    private var effectiveScheme: ColorScheme {
        Theme.effectiveScheme(appearance: store.config.appearance, system: systemScheme)
    }

    private var fontSize: CGFloat { Theme.inputFontSize() }

    private var filterFontSize: CGFloat {
        #if os(macOS)
        return 14
        #else
        return fontSize
        #endif
    }

    private var mode: Binding<BitsMode> {
        Binding(
            get: { bits.showingArchive ? .archive : .bits },
            set: { newMode in
                Task { await bits.setShowingArchive(newMode == .archive, config: store.config) }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Centered on iOS/iPadOS, leading on Mac — same as Tasks'
                // filter row.
                #if os(iOS)
                Spacer()
                #endif
                PillFilterBar(
                    items: BitsMode.allCases, label: \.rawValue,
                    selection: mode, scheme: effectiveScheme, fontSize: filterFontSize
                )
                Spacer()
                if bits.isLoading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 20)
            .frame(height: Theme.headerRowHeight)
            .foregroundStyle(Theme.primary(effectiveScheme))

            ContentBox(scheme: effectiveScheme, bordered: false) {
                content
            }
            .padding(.top, 16)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { Task { await bits.load(store.config) } }
        .onChange(of: isActive) {
            if isActive { Task { await bits.load(store.config) } }
        }
        .onChange(of: store.config.bitsTableId) {
            Task { await bits.load(store.config) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !store.config.isBitsConfigured {
            placeholder("Choose your Bits table in Settings.")
        } else if let message = bits.errorMessage, bits.bits.isEmpty {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        } else if bits.bits.isEmpty {
            placeholder(bits.isLoading ? "Loading…"
                        : bits.showingArchive ? "Nothing archived yet." : "Nothing captured yet.")
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if let message = bits.errorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(bits.bits) { bit in
                        BitCard(
                            bit: bit, isArchive: bits.showingArchive,
                            store: store, bits: bits, scheme: effectiveScheme, fontSize: fontSize
                        )
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: fontSize))
            .foregroundStyle(Theme.secondaryText(effectiveScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
    }
}

/// One Bit as a card: very subtle fill plus the same hairline rounded border
/// the app's text fields use.
private struct BitCard: View {
    let bit: Bit
    let isArchive: Bool
    @ObservedObject var store: TaskStore
    @ObservedObject var bits: BitsStore
    let scheme: ColorScheme
    let fontSize: CGFloat

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isSaving = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isEditing {
                PlainTextEditor(text: $draft, fontSize: fontSize, scheme: scheme)
                    .frame(minHeight: 110, maxHeight: 320)
                HStack(spacing: 10) {
                    Spacer()
                    PillActionButton(label: "Cancel", scheme: scheme) { isEditing = false }
                    PillActionButton(label: isSaving ? "Saving…" : "Save", scheme: scheme, action: save)
                        .disabled(isSaving)
                }
            } else {
                Text(bit.text)
                    .font(.system(size: fontSize))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { if !isArchive { beginEditing() } }

                HStack(spacing: 4) {
                    Text(bit.displayDate)
                        .font(.system(size: fontSize * 0.75))
                        .foregroundStyle(Theme.secondaryText(scheme))
                    Spacer()
                    if !isArchive { action("Edit", beginEditing) }
                    action(copied ? "Copied" : "Copy", copy)
                    action(isArchive ? "Restore" : "Archive") {
                        Task { await bits.setArchived(bit, archived: !isArchive, config: store.config) }
                    }
                    action("Delete") {
                        Task { await bits.delete(bit, config: store.config) }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.primary(scheme).opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.primary(scheme).opacity(Theme.borderOpacity), lineWidth: Theme.borderWidth)
        )
    }

    private func action(_ title: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .font(.system(size: fontSize * 0.8, weight: .medium))
                .foregroundStyle(Theme.secondaryText(scheme))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func beginEditing() {
        draft = bit.text
        isEditing = true
    }

    private func save() {
        let newText = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newText.isEmpty, newText != bit.text else {
            isEditing = false
            return
        }
        isSaving = true
        Task {
            let ok = await bits.saveEdit(bit, text: newText, config: store.config)
            isSaving = false
            if ok { isEditing = false }
        }
    }

    private func copy() {
        #if os(iOS)
        UIPasteboard.general.string = bit.text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(bit.text, forType: .string)
        #endif
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }
}
