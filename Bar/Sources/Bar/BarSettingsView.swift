import AppKit
import Carbon.HIToolbox
import SwiftUI
import ArthurKit

/// Lets Brandon rebind either of ArthurBar's two global hotkeys — reintroduced
/// in the same shape as craft-quick-capture's own hotkey-recorder settings
/// screen: click a shortcut, then press the new key combo, captured via a
/// local NSEvent monitor and encoded through HotKeySpec (which already wraps
/// Carbon's RegisterEventHotKey underneath, in HotKey.swift).
struct BarSettingsView: View {
    enum Row: Equatable { case clip, addTask, quickCapture }

    @State private var hotKeys: BarHotKeys
    @State private var recordingRow: Row?
    @State private var monitor: Any?
    @State private var message: String?

    /// Applies the new shortcut for `row`; returns false if it couldn't be
    /// registered (e.g. another app already owns that combo).
    let onApply: (Row, HotKeySpec) -> Bool

    init(hotKeys: BarHotKeys, onApply: @escaping (Row, HotKeySpec) -> Bool) {
        _hotKeys = State(initialValue: hotKeys)
        self.onApply = onApply
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ClipPageSection()
            Divider()
            Text("Hotkeys").font(.system(size: 13, weight: .semibold))
            row(title: "Clip Selection", row: .clip, spec: hotKeys.clip)
            row(title: "Quick Task", row: .addTask, spec: hotKeys.addTask)
            row(title: "Quick Capture", row: .quickCapture, spec: hotKeys.quickCapture)
            Text(message ?? "Click a shortcut, then press the new key combo. Include ⌘, ⌥, or ⌃.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 400)
        // Arthur's own light / dark choice, same as the main app.
        .background(BarTheme.background(BarTheme.scheme))
        .preferredColorScheme(BarTheme.scheme)
        .onDisappear { stopRecording() }
    }

    private func row(title: String, row: Row, spec: HotKeySpec) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                toggleRecording(row)
            } label: {
                Text(recordingRow == row ? "Type shortcut…" : spec.display)
                    .frame(minWidth: 90)
            }
            .keyboardShortcut(.none)
            Button("Reset") { apply(row, defaultSpec(for: row)) }
                .disabled(spec == defaultSpec(for: row))
        }
    }

    private func defaultSpec(for row: Row) -> HotKeySpec {
        switch row {
        case .clip: return BarHotKeys.defaultClip
        case .addTask: return BarHotKeys.defaultAddTask
        case .quickCapture: return BarHotKeys.defaultQuickCapture
        }
    }

    private func toggleRecording(_ row: Row) {
        recordingRow == row ? stopRecording() : startRecording(row)
    }

    private func startRecording(_ row: Row) {
        stopRecording()
        recordingRow = row
        message = "Press the new shortcut (esc cancels)…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // esc
                stopRecording()
                message = nil
                return nil
            }
            let mods = HotKeySpec.carbonModifiers(from: event.modifierFlags)
            let required = UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)
            guard mods & required != 0 else {
                message = "Include at least one of ⌘, ⌥, or ⌃."
                return nil
            }
            let newSpec = HotKeySpec.from(event: event)
            stopRecording()
            apply(row, newSpec)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recordingRow = nil
    }

    private func apply(_ row: Row, _ spec: HotKeySpec) {
        if onApply(row, spec) {
            switch row {
            case .clip: hotKeys.clip = spec
            case .addTask: hotKeys.addTask = spec
            case .quickCapture: hotKeys.quickCapture = spec
            }
            message = nil
        } else {
            message = "Couldn't register \(spec.display) — another app may own it."
        }
    }
}


/// Where clips go, and whether ArthurBar is allowed to read the selection.
struct ClipPageSection: View {
    @StateObject private var documentStore = DocumentStore()
    @State private var page = ClipStore.page
    @State private var isChoosing = false
    @State private var query = ""
    @State private var trusted = SelectionGrabber.isTrusted

    private var scheme: ColorScheme { BarTheme.scheme }
    private var results: [CraftDocument] { documentStore.search(query, limit: 5) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clip Selection").font(.system(size: 13, weight: .semibold))

            HStack {
                Text("Clip page")
                Spacer()
                Text(page?.title ?? "Not chosen")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button(isChoosing ? "Cancel" : (page == nil ? "Choose…" : "Change")) {
                    isChoosing.toggle()
                    query = ""
                }
            }

            if isChoosing {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        TextField("Search documents…", text: $query)
                            .textFieldStyle(.plain)
                        Button(documentStore.isRefreshing ? "Refreshing…" : "Refresh") {
                            documentStore.refresh(craftLink: Config.load().craftLink)
                        }
                        .disabled(documentStore.isRefreshing)
                    }
                    .padding(10)
                    if !results.isEmpty {
                        Divider()
                        ForEach(results) { doc in
                            Button {
                                page = ClipPage(id: doc.id, title: doc.title)
                                ClipStore.page = page
                                isChoosing = false
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(doc.title).lineLimit(1)
                                    if let folder = doc.folder {
                                        Text(folder).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: BarTheme.cornerRadius, style: .continuous)
                        .fill(BarTheme.card(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BarTheme.cornerRadius, style: .continuous)
                        .stroke(BarTheme.text(scheme).opacity(0.2), lineWidth: 0.5)
                )
            }

            HStack {
                Text("Accessibility")
                Spacer()
                if trusted {
                    Text("Allowed").foregroundStyle(.secondary)
                } else {
                    Button("Allow…") {
                        SelectionGrabber.requestPermission()
                    }
                }
            }
            Text("Select text in any app and press the hotkey: it's added to the clip page as plain text. With nothing selected, a copied image or text is sent instead.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            documentStore.refreshIfStale(craftLink: Config.load().craftLink)
            trusted = SelectionGrabber.isTrusted
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = SelectionGrabber.isTrusted
        }
    }
}
