import Foundation

/// Shared Craft Quick Capture draft — lives at the App level, injected via
/// `.environmentObject` at the WindowGroup scene, rather than as local
/// `@State` inside QuickCaptureView. Originally this was also what let a
/// Mac-only pop-out capture window mirror the main window's in-progress
/// text; that pop-out was removed once the sidebar redesign made the main
/// window collapsible (Brandon: no longer needed a separate expanded
/// window for the same purpose). Kept as an environment object rather than
/// reverted to local state since QuickCaptureView is already never
/// destroyed/recreated across tab switches (the opacity-swap pattern), so
/// there's no behavior difference either way — just no reason to churn it.
@MainActor
final class QuickCaptureDraft: ObservableObject {
    @Published var text = ""
    @Published var addSeparator = true

    func reset() {
        text = ""
        addSeparator = true
    }
}
