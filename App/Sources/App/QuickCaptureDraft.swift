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
/// Where the Quick Capture screen sends what you've typed. The Destination
/// card at the bottom of the screen switches between these.
enum CaptureTarget: String, CaseIterable, Identifiable {
    case bits = "Bits"
    case newPage = "New Craft Page"
    case page = "Append Craft Page"
    case task = "New Craft Task"
    case reflection = "Reflection"
    case baserow = "Baserow"
    var id: String { rawValue }
}

@MainActor
final class QuickCaptureDraft: ObservableObject {
    @Published var text = ""
    @Published var addSeparator = true
    @Published var target: CaptureTarget = .page

    func reset() {
        text = ""
        addSeparator = true
    }
}
