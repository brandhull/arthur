import AppKit
import CoreGraphics

/// Lets the user drag over part of the screen, using macOS's own selection
/// tool, and hands back the picture. It goes through a temporary file, so the
/// clipboard is left alone. Needs Screen Recording permission.
@MainActor
enum ScreenshotCapture {
    static var isAllowed: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time; after that macOS stays quiet
    /// and the switch lives in System Settings.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    static func openSettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
    }

    /// The selected area as PNG data, or nil if the user pressed Escape.
    static func selectArea() async throws -> Data? {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("arthurbar-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i: interactive selection (Space switches to picking a window).
        process.arguments = ["-i", "-tpng", file.path]
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in done.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                done.resume(throwing: error)
            }
        }
        return try? Data(contentsOf: file)
    }
}
