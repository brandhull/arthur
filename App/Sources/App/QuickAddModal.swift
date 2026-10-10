import SwiftUI
import ArthurKit

/// The bubble.and.pencil quick-add popup's content: a plain list of five
/// rows. Task opens AddTaskSheet; Quick Capture just switches the selected
/// tab; Bits, Reflection and Document each open a full capture screen
/// embedded in AgendaView's tabContent (TextCaptureView / DocumentCaptureSheet)
/// rather than anything inside this popup.
///
/// Platform-neutral — every size here is Theme.inputFontSize(). Pure content
/// only — CenteredModal (mounted once at AgendaView's top level, identical on
/// every platform) owns the outer card's frame, background, border and close
/// button.
struct QuickAddModal: View {
    @ObservedObject var store: TaskStore
    @Binding var selectedTab: HomeTab
    @Binding var showingAddTask: Bool
    @Binding var showingDocumentCapture: Bool
    @Binding var showingBitCapture: Bool
    @Binding var showingReflectionCapture: Bool
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var systemScheme

    private var effectiveScheme: ColorScheme {
        Theme.effectiveScheme(appearance: store.config.appearance, system: systemScheme)
    }

    var body: some View {
        menuBody
            .foregroundStyle(Theme.primary(effectiveScheme))
    }

    private var menuBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            quickAddRow(title: "Task") {
                isPresented = false
                showingAddTask = true
            }
            Divider()
            quickAddRow(title: "Quick Capture") {
                isPresented = false
                selectedTab = .quickCapture
            }
            Divider()
            quickAddRow(title: "Bits") {
                isPresented = false
                showingBitCapture = true
            }
            Divider()
            quickAddRow(title: "Document") {
                isPresented = false
                showingDocumentCapture = true
            }
            Divider()
            quickAddRow(title: "Reflection") {
                isPresented = false
                showingReflectionCapture = true
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private func quickAddRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: Theme.inputFontSize()))
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
