import SwiftUI
import ArthurKit

/// Interaction model (SCOPE.md "Task row interactions"):
///  - tap checkbox -> mark done
///  - tap text -> inline edit
///  - long-press + confirmation -> open the block in Craft via its clickableLink
struct TaskRowView: View {
    let task: CraftTask
    @ObservedObject var store: TaskStore
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var isEditing = false
    @State private var editedText = ""
    @State private var showingOpenConfirm = false

    private var textFontSize: CGFloat {
        #if os(iOS)
        return Theme.inputFontSize(horizontalSizeClass: horizontalSizeClass)
        #else
        return Theme.inputFontSize()
        #endif
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                store.toggleDone(task)
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.done ? Theme.accentDim : Theme.accentBright)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("Task", text: $editedText, onCommit: commitEdit)
                        .font(.system(size: textFontSize))
                } else {
                    Text(task.text)
                        .font(.system(size: textFontSize))
                        .lineSpacing(3)
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? .secondary : .primary)
                        .onTapGesture {
                            editedText = task.text
                            isEditing = true
                        }
                }
                HStack(spacing: 8) {
                    if let container = task.containerTitle {
                        Text(container)
                            .font(.system(size: textFontSize))
                            .foregroundStyle(.secondary)
                    }
                    // Every task reaching this row already has a date — both
                    // Today and Tomorrow filter on taskDate being non-nil, so
                    // there's no "no date yet" case to design an add-date
                    // affordance for here. .compact style natively behaves
                    // as "tap to get an inline picker" — it shows the date
                    // as plain-looking text until tapped, then opens the
                    // platform's own compact picker (a popover on iOS, a
                    // small calendar on Mac).
                    //
                    // The visible date text below is a plain Text, not
                    // .compact's own label — that native label is backed by
                    // UIDatePicker/NSDatePicker chrome that ignores .font()
                    // (confirmed: it stayed noticeably larger/bolder than
                    // the task text and container caption no matter what
                    // size was requested, the exact inconsistency Brandon
                    // flagged). The real DatePicker is still here for the
                    // tap-to-edit interaction, just made invisible and
                    // layered behind the correctly-sized Text so tapping it
                    // still opens the native picker.
                    if let date = task.scheduleDate ?? task.deadlineDate {
                        ZStack {
                            Text(date, format: .dateTime.month(.abbreviated).day().year())
                                .font(.system(size: textFontSize))
                                .foregroundStyle(.secondary)
                            DatePicker("", selection: dateBinding(fallback: date), displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .opacity(0.02)
                        }
                        .fixedSize()
                    }
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onLongPressGesture {
            showingOpenConfirm = true
        }
        .confirmationDialog("Open in Craft?", isPresented: $showingOpenConfirm, titleVisibility: .visible) {
            Button("Open in Craft") { Task { await openInCraft() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func dateBinding(fallback: Date) -> Binding<Date> {
        Binding(
            get: { task.scheduleDate ?? task.deadlineDate ?? fallback },
            set: { store.updateDueDate(task, newDate: $0) }
        )
    }

    private func commitEdit() {
        isEditing = false
        guard editedText != task.text else { return }
        store.updateText(task, newText: editedText)
    }

    private func openInCraft() async {
        guard let url = await store.clickableLink(for: task) else { return }
        #if os(iOS)
        await UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
}
