import Foundation

/// Shared Craft Quick Capture draft — lives at the App level, injected via
/// `.environmentObject` into every scene, rather than as local `@State`
/// inside QuickCaptureView. This is what lets the Mac-only pop-out window
/// (QuickCapturePopoutView) and the main window's Quick Capture tab show
/// the exact same in-progress text: one shared source of truth, not a
/// copy-on-open/copy-back-on-return handoff. Typing in either window
/// updates the same property, so closing the pop-out via its red traffic
/// light (not just its "return" button) never loses anything — there was
/// never a separate copy to lose.
@MainActor
final class QuickCaptureDraft: ObservableObject {
    @Published var text = ""
    @Published var addSeparator = true

    func reset() {
        text = ""
        addSeparator = true
    }
}
