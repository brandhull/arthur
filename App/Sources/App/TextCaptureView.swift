import SwiftUI
import ArthurKit

/// The blank capture screen behind the New menu's Bits and Reflection rows —
/// the same screen as Quick Capture's Craft mode (a big text box filling the
/// pane), except there's no destination to pick, so Save is just a button at
/// the bottom right that appears once there's something to save. Embedded as
/// an opacity-swapped layer in AgendaView's tabContent, same as
/// DocumentCaptureSheet, so the sidebar/hamburger stays reachable.
///
/// What "save" means is up to the caller: `save` returns nil on success or an
/// error message, and `onSaved` then runs (e.g. switch to the tab that shows
/// the result) before this closes itself.
struct TextCaptureView: View {
    @ObservedObject var store: TaskStore
    @Binding var isPresented: Bool
    let save: (String) async -> String?
    let onSaved: () -> Void
    @Environment(\.colorScheme) private var systemScheme

    @State private var text = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var effectiveScheme: ColorScheme {
        Theme.effectiveScheme(appearance: store.config.appearance, system: systemScheme)
    }

    private var inputFontSize: CGFloat { Theme.inputFontSize() }

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

            // No Save button (or surrounding container) until there's text.
            if hasText || errorMessage != nil {
                VStack(alignment: .trailing, spacing: 8) {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if hasText {
                        PillButton(systemImage: "arrow.up.circle", label: isSaving ? "Saving…" : "Save", action: submit)
                            .disabled(isSaving)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hasText)
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

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        errorMessage = nil
        Task {
            let failure = await save(trimmed)
            isSaving = false
            if let failure {
                errorMessage = failure
            } else {
                text = ""
                onSaved()
                isPresented = false
            }
        }
    }
}
