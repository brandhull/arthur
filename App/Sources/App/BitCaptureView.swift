import SwiftUI
import ArthurKit

/// The "Bits" quick-add flow — the same blank capture screen as Quick
/// Capture's Craft mode (a big text box filling the pane, a bottom card),
/// except there's no destination: the card holds just Save. Embedded as an
/// opacity-swapped layer in AgendaView's tabContent, same as
/// DocumentCaptureSheet, so the sidebar/hamburger stays reachable. Saving
/// closes this and switches to the Bits tab, where the new Bit is on top.
struct BitCaptureView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var bits: BitsStore
    @Binding var isPresented: Bool
    @Binding var selectedTab: HomeTab
    @Environment(\.colorScheme) private var systemScheme

    @State private var text = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var effectiveScheme: ColorScheme {
        Theme.effectiveScheme(appearance: store.config.appearance, system: systemScheme)
    }

    private var inputFontSize: CGFloat { Theme.inputFontSize() }

    private var cardHorizontalInset: CGFloat {
        #if os(macOS)
        return Theme.sidebarCardInset
        #else
        return 16
        #endif
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            FieldBox(scheme: effectiveScheme, bordered: false) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Nothing here yet.")
                            .font(.system(size: inputFontSize))
                            .foregroundStyle(Theme.secondaryText(effectiveScheme))
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                    PlainTextEditor(
                        text: $text, fontSize: inputFontSize, scheme: effectiveScheme, autoFocusWhen: isPresented
                    )
                    .frame(minHeight: 120, maxHeight: .infinity)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 16)
            .frame(maxHeight: .infinity)

            VStack(alignment: .trailing, spacing: 8) {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                PillButton(systemImage: "arrow.up.circle", label: isSaving ? "Saving…" : "Save", action: save)
                    .disabled(!canSave)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.sidebarCardCornerRadius, style: .continuous)
                    .fill(Theme.sidebarCardBackground(effectiveScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.sidebarCardCornerRadius, style: .continuous)
                    .stroke(Theme.primary(effectiveScheme).opacity(Theme.borderOpacity), lineWidth: Theme.borderWidth)
            )
            .padding(.horizontal, cardHorizontalInset)
            .padding(.bottom, Theme.sidebarCardInset)
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
    }

    private func save() {
        guard store.config.isBitsConfigured else {
            errorMessage = "Choose your Bits table in Settings."
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        errorMessage = nil
        Task {
            let ok = await bits.add(text: trimmed, config: store.config)
            isSaving = false
            if ok {
                text = ""
                selectedTab = .bits
                isPresented = false
            } else {
                errorMessage = bits.errorMessage
            }
        }
    }
}
