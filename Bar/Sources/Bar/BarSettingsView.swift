import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Lets Brandon rebind either of ArthurBar's two global hotkeys — reintroduced
/// in the same shape as craft-quick-capture's own hotkey-recorder settings
/// screen: click a shortcut, then press the new key combo, captured via a
/// local NSEvent monitor and encoded through HotKeySpec (which already wraps
/// Carbon's RegisterEventHotKey underneath, in HotKey.swift).
struct BarSettingsView: View {
    enum Row: Equatable { case addTask, quickCapture }

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
            Text("Hotkeys").font(.system(size: 13, weight: .semibold))
            row(title: "Quick Task", row: .addTask, spec: hotKeys.addTask)
            row(title: "Quick Capture", row: .quickCapture, spec: hotKeys.quickCapture)
            Text(message ?? "Click a shortcut, then press the new key combo. Include ⌘, ⌥, or ⌃.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 360)
        // Always dark — same as ArthurBar's two panels; this window was the
        // one place still following the system appearance.
        .preferredColorScheme(.dark)
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
        row == .addTask ? BarHotKeys.defaultAddTask : BarHotKeys.defaultQuickCapture
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
            case .addTask: hotKeys.addTask = spec
            case .quickCapture: hotKeys.quickCapture = spec
            }
            message = nil
        } else {
            message = "Couldn't register \(spec.display) — another app may own it."
        }
    }
}
