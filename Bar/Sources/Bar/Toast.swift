import AppKit
import SwiftUI

/// A small, quiet confirmation that appears near the top of the screen and
/// fades away. Never takes focus, so the app you were in stays in front.
@MainActor
final class Toast {
    static let shared = Toast()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ message: String, isError: Bool = false) {
        hideTask?.cancel()
        panel?.orderOut(nil)

        let hosting = NSHostingView(rootView: ToastView(message: message, isError: isError, scheme: BarTheme.scheme))
        let size = hosting.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.contentView = hosting
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 24))
        }
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; p.animator().alphaValue = 1 }
        panel = p

        let hold: UInt64 = isError ? 3_500_000_000 : 1_800_000_000
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: hold)
            guard !Task.isCancelled, let self, let p = self.panel else { return }
            await NSAnimationContext.runAnimationGroup { $0.duration = 0.25; p.animator().alphaValue = 0 }
            if !Task.isCancelled { p.orderOut(nil) }
        }
    }
}

private struct ToastView: View {
    let message: String
    let isError: Bool
    let scheme: ColorScheme

    var body: some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isError ? Color.red : BarTheme.text(scheme))
            .lineLimit(2)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: BarTheme.cornerRadius, style: .continuous)
                    .fill(BarTheme.card(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BarTheme.cornerRadius, style: .continuous)
                    .stroke(BarTheme.text(scheme).opacity(0.2), lineWidth: 0.5)
            )
            .padding(12) // room for the window shadow
            .fixedSize()
    }
}
