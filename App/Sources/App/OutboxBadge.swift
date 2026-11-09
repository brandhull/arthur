import SwiftUI
import ArthurKit

/// Small "N waiting to send" capsule shown only while the outbox has
/// something in it. Tap for the list (Retry / Copy / Discard).
struct OutboxBadge: View {
    @ObservedObject var outbox: OutboxStore
    let scheme: ColorScheme
    @State private var showingList = false

    var body: some View {
        if !outbox.items.isEmpty {
            Button { showingList = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: outbox.attentionCount > 0 ? "exclamationmark.circle" : "clock")
                    Text(label)
                }
                .font(.caption)
                .foregroundStyle(outbox.attentionCount > 0 ? Color.red : Theme.secondaryText(scheme))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.background(scheme)))
                .overlay(Capsule().stroke(Theme.secondaryText(scheme).opacity(0.4), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .padding(12)
            .sheet(isPresented: $showingList) { OutboxListView(outbox: outbox, scheme: scheme) }
        }
    }

    private var label: String {
        var parts: [String] = []
        if outbox.pendingCount > 0 { parts.append("\(outbox.pendingCount) waiting to send") }
        if outbox.attentionCount > 0 { parts.append("\(outbox.attentionCount) needs attention") }
        return parts.joined(separator: " · ")
    }
}

struct OutboxListView: View {
    @ObservedObject var outbox: OutboxStore
    let scheme: ColorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Waiting to send").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.plain)
            }
            .padding(16)
            Divider()
            if outbox.items.isEmpty {
                Text("Nothing waiting.").foregroundStyle(Theme.secondaryText(scheme)).padding(16)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(outbox.items) { item in
                            row(item)
                            Divider()
                        }
                    }
                }
            }
        }
        .foregroundStyle(Theme.primary(scheme))
        .background(Theme.background(scheme))
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
        .onChange(of: outbox.items.isEmpty) { if outbox.items.isEmpty { dismiss() } }
    }

    private func row(_ item: OutboxItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.label).font(.caption).foregroundStyle(Theme.secondaryText(scheme))
            Text(item.text).lineLimit(4)
            if let failure = item.failure {
                Text(failure).font(.caption).foregroundStyle(.red)
            }
            HStack(spacing: 16) {
                if item.failure != nil {
                    Button("Retry") { Task { await outbox.retry(item) } }
                }
                Button("Copy") { copy(item.text) }
                Button("Discard", role: .destructive) { outbox.discard(item) }
            }
            .font(.caption)
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
