import SwiftUI
import ArthurKit

/// Both due date and destination are optional (SCOPE.md "Adding a task"):
/// no date = task shows only under "All"; no destination = falls back to
/// Craft's standard inbox unless Settings has an explicit default inbox doc
/// set (nil default deliberately means "standard inbox," not "first
/// configured doc" — see Config.defaultInbox).
///
/// Built with FieldBox/FieldLabel rather than native Form — Brandon wanted
/// every input sheet's corner radius to match the home screen's 8pt
/// (ContentBox/PillButton/Tasks List), which native Form's grouped-section
/// rounding can't be made to match.
struct AddTaskSheet: View {
    @ObservedObject var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemScheme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var text = ""
    @State private var includeDueDate = false
    @State private var dueDate = Date()
    @State private var destinationId: String?

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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FieldLabel(title: "Task")
                    FieldBox(scheme: effectiveScheme) {
                        TextField("", text: $text)
                            .textFieldStyle(.plain)
                            .font(.system(size: inputFontSize))
                            .multilineTextAlignment(.leading)
                            .padding(12)
                    }

                    FieldLabel(title: "Due date (optional)")
                    FieldBox(scheme: effectiveScheme) {
                        VStack(alignment: .leading, spacing: 0) {
                            Toggle("Set a due date", isOn: $includeDueDate)
                                .font(.system(size: inputFontSize))
                                .padding(12)
                            if includeDueDate {
                                Divider().padding(.leading, 12)
                                DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                                    .padding(12)
                            }
                        }
                    }

                    // A native Picker here (as this used to be) ignores
                    // explicit .font() sizing for its displayed value on
                    // iOS — the exact "Bits"/"Brandon" bug Brandon flagged
                    // in Baserow's Quick Capture form. Same MenuFieldPicker
                    // fix applied here for the same reason.
                    FieldLabel(title: "Destination (optional)")
                    FieldBox(scheme: effectiveScheme) {
                        MenuFieldPicker(
                            placeholder: "Default (\(store.config.defaultInbox?.name ?? "Craft Inbox"))",
                            options: store.config.inboxes.map { (label: $0.name, value: Optional($0.id)) },
                            noneValue: Optional<String>.none,
                            selection: $destinationId, fontSize: inputFontSize, scheme: effectiveScheme
                        )
                    }
                }
                .padding(.bottom, 16)
            }
            .foregroundStyle(Theme.primary(effectiveScheme))
            .background(Theme.background(effectiveScheme))
            .navigationTitle("Add Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let destination = store.config.inboxes.first { $0.id == destinationId } ?? store.config.defaultInbox
                        store.addTask(text: text, dueDate: includeDueDate ? dueDate : nil, destination: destination)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .preferredColorScheme(store.config.appearance == .system ? nil : effectiveScheme)
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 320, idealHeight: 360)
        #endif
    }
}
