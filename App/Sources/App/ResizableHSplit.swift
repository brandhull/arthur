#if os(macOS)
import SwiftUI
import AppKit

/// A resizable, collapsible two-pane horizontal split, replacing SwiftUI's
/// own `HSplitView` for the sidebar redesign specifically because
/// `HSplitView` always draws AppKit's default divider — a solid line with
/// no exposed styling hook — which read as a harsh black vertical bar next
/// to the sidebar's own floating, bordered card (Brandon's "Maverick"
/// reference has no visible divider line at all, just the two panes sitting
/// side by side). `NSSplitView` itself supports overriding `dividerColor`,
/// just not through the SwiftUI wrapper, so this drops one level to a
/// custom `NSViewControllerRepresentable` wrapping `NSSplitViewController`
/// with that override in place.
///
/// Collapse is driven by `NSSplitViewItem.isCollapsed` rather than
/// conditionally including/excluding the leading view from a plain
/// SwiftUI `if` — that property already handles the show/hide affordance
/// AppKit's own way, and unlike a container that gets removed and
/// recreated, this is the same NSSplitViewItem before and after, avoiding
/// any risk of the leading pane's hosted SwiftUI view identity resetting.
private final class InvisibleDividerSplitView: NSSplitView {
    override var dividerColor: NSColor { .clear }
}

struct ResizableHSplit<Leading: View, Trailing: View>: NSViewControllerRepresentable {
    @Binding var isCollapsed: Bool
    let leadingMinWidth: CGFloat
    let leadingIdealWidth: CGFloat
    let leadingMaxWidth: CGFloat
    let leading: Leading
    let trailing: Trailing

    init(
        isCollapsed: Binding<Bool>, leadingMinWidth: CGFloat, leadingIdealWidth: CGFloat, leadingMaxWidth: CGFloat,
        @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing
    ) {
        self._isCollapsed = isCollapsed
        self.leadingMinWidth = leadingMinWidth
        self.leadingIdealWidth = leadingIdealWidth
        self.leadingMaxWidth = leadingMaxWidth
        self.leading = leading()
        self.trailing = trailing()
    }

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = NSSplitViewController()
        let splitView = InvisibleDividerSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        controller.splitView = splitView

        // Plain viewController item, not sidebarWithViewController: — that
        // convenience initializer opts into AppKit's automatic vibrancy/
        // material behind the pane, which would fight the sidebar's own
        // precisely-colored, rounded-and-bordered card drawn in SwiftUI
        // (Theme.sidebarCardBackground) rather than complementing it.
        let leadingHosting = NSHostingController(rootView: leading)
        let leadingItem = NSSplitViewItem(viewController: leadingHosting)
        leadingItem.minimumThickness = leadingMinWidth
        leadingItem.maximumThickness = leadingMaxWidth
        // Drag-to-collapse and double-click-to-collapse are both off —
        // collapse only ever happens through the sidebar's own toggle
        // button (isCollapsed), not an accidental drag past the minimum.
        leadingItem.canCollapse = false
        leadingItem.isCollapsed = isCollapsed
        controller.addSplitViewItem(leadingItem)

        let trailingHosting = NSHostingController(rootView: trailing)
        let trailingItem = NSSplitViewItem(viewController: trailingHosting)
        controller.addSplitViewItem(trailingItem)

        context.coordinator.leadingHosting = leadingHosting
        context.coordinator.trailingHosting = trailingHosting
        context.coordinator.leadingItem = leadingItem
        return controller
    }

    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        context.coordinator.leadingHosting?.rootView = leading
        context.coordinator.trailingHosting?.rootView = trailing
        if context.coordinator.leadingItem?.isCollapsed != isCollapsed {
            withAnimation {
                context.coordinator.leadingItem?.animator().isCollapsed = isCollapsed
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var leadingHosting: NSHostingController<Leading>?
        var trailingHosting: NSHostingController<Trailing>?
        var leadingItem: NSSplitViewItem?
    }
}
#endif
