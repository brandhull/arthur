import SwiftUI
import ArthurKit

/// The Mac menu bar quick-add panel (SCOPE.md "Mac menu bar quick-add") —
/// mirrors craft-quick-capture's panel pattern: text field + destination
/// picker among the same inbox docs configured in the main app.
struct QuickAddView: View {
    let onSubmit: () -> Void

    @State private var text = ""
    @State private var destinationId: String?
    @State private var includeDueDate = false
    @State private var dueDate = Date()
    @State private var config = Config.load()
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Task").font(.headline)
            TextField("What needs doing?", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            Toggle("Set a due date", isOn: $includeDueDate)
            if includeDueDate {
                DatePicker("Date", selection: $dueDate, displayedComponents: .date)
            }

            if !config.inboxes.isEmpty {
                Picker("Inbox", selection: $destinationId) {
                    Text("Default (\(config.defaultInbox?.name ?? "Craft Inbox"))").tag(String?.none)
                    ForEach(config.inboxes) { inbox in
                        Text(inbox.name).tag(String?.some(inbox.id))
                    }
                }
            } else {
                Text("No inbox documents configured yet — open Arthur's Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Add", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
            }
        }
        .padding()
        // Extra breathing room specifically under the Add button — the
        // uniform .padding() above already covers the other three edges,
        // but the button sat flush against the window's bottom border
        // (see AppDelegate's sizingOptions comment for the sizing half of
        // this fix).
        .padding(.bottom, 8)
        // Reports this view's actual height to the hosting NSPanel (via
        // NSHostingController.sizingOptions in AppDelegate) instead of
        // stretching to fill whatever frame it's given — this is what lets
        // the panel grow when the due-date picker appears and shrink back
        // when it's hidden, rather than clipping into a fixed size.
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 340)
        .onAppear { config = Config.load() }
    }

    private func submit() {
        guard !config.craftLink.isEmpty else {
            errorMessage = "Set your Craft link in Arthur's Settings first."
            return
        }
        let destination = config.inboxes.first { $0.id == destinationId } ?? config.defaultInbox
        isSubmitting = true
        let client = CraftClient(url: config.craftLink)
        let submittedText = text
        // Same yyyy-MM-dd/.current-timezone formatting as TaskStore.isoDay
        // in the main app — kept as a local static here rather than shared,
        // since it's one line and Bar doesn't otherwise depend on the App
        // target.
        let schedule = includeDueDate ? Self.isoDay(dueDate) : nil
        Task {
            do {
                try await client.addTask(markdown: submittedText, schedule: schedule, deadline: nil,
                                          destinationBlockId: destination?.id)
                text = ""
                includeDueDate = false
                dueDate = Date()
                isSubmitting = false
                onSubmit()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    private static func isoDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }
}
