import AppKit
import SwiftUI
import ArthurKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var addTaskHotKey: HotKey?
    private var addTaskPanel: NSPanel?
    private var quickCaptureHotKey: HotKey?
    private var quickCapturePanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "ArthurBar"
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "checkmark.rectangle.stack", accessibilityDescription: "Arthur Quick Task")
            // Without isTemplate, this rendered as a plain black glyph
            // regardless of menu bar theme/highlight state — every other
            // icon in the menu bar is a template image (monochrome,
            // automatically inverts on dark backgrounds and when an item
            // is highlighted/clicked), which is what made ArthurBar's
            // stand out next to them. 14pt still read visibly smaller than
            // its neighbors (Brandon flagged it after the isTemplate fix);
            // 17pt is the standard NSStatusItem glyph size most menu bar
            // apps actually use.
            image?.isTemplate = true
            button.image = image?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
            )
        }
        statusItem.menu = buildMenu()

        // ⌥⌘A by default — distinct from craft-quick-capture's ⌥⌘Space so both
        // menu bar apps can run side by side without a shortcut collision.
        addTaskHotKey = HotKey(keyCode: 0, modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            self?.toggleAddTaskPanel()
        }
        // ⌥⌘C ("Capture") — a second, separate hotkey/popup rather than
        // folding this into Quick Add with a mode switch: Brandon still
        // uses task quick-add regularly, so each stays focused on one job.
        // keyCode 8 = 'C'. Also distinct from craft-quick-capture's
        // ⌥⌘Space, same reasoning as above.
        quickCaptureHotKey = HotKey(keyCode: 8, modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            self?.toggleQuickCapturePanel()
        }
    }

    private func toggleAddTaskPanel() {
        if let addTaskPanel, addTaskPanel.isVisible {
            addTaskPanel.orderOut(nil)
            return
        }
        showAddTaskPanel()
    }

    private func showAddTaskPanel() {
        if addTaskPanel == nil {
            let view = QuickAddView(onSubmit: { [weak self] in self?.addTaskPanel?.orderOut(nil) })
            let hosting = NSHostingController(rootView: view)
            // Lets the panel track the SwiftUI content's own ideal height
            // instead of a fixed size — without this, showing the due-date
            // picker (an extra row) had nowhere to go inside the fixed
            // 380x200 frame, so it just compressed everything including
            // the padding below the Add button, leaving it flush against
            // the window's bottom edge. QuickAddView's own .fixedSize(...)
            // is what makes it report a real height for this to follow.
            hosting.sizingOptions = [.preferredContentSize]
            let p = NSPanel(contentViewController: hosting)
            p.styleMask = [.titled, .closable, .nonactivatingPanel]
            p.title = "Quick Task"
            p.isFloatingPanel = true
            p.level = .floating
            addTaskPanel = p
        }
        NSApp.activate(ignoringOtherApps: true)
        addTaskPanel?.center()
        addTaskPanel?.makeKeyAndOrderFront(nil)
    }

    private func toggleQuickCapturePanel() {
        if let quickCapturePanel, quickCapturePanel.isVisible {
            quickCapturePanel.orderOut(nil)
            return
        }
        showQuickCapturePanel()
    }

    private func showQuickCapturePanel() {
        if quickCapturePanel == nil {
            let view = QuickCaptureBarView(onSubmit: { [weak self] in self?.quickCapturePanel?.orderOut(nil) })
            let hosting = NSHostingController(rootView: view)
            let p = NSPanel(contentViewController: hosting)
            p.styleMask = [.titled, .closable, .nonactivatingPanel]
            p.title = "Quick Capture"
            p.isFloatingPanel = true
            p.level = .floating
            p.setContentSize(NSSize(width: 380, height: 340))
            quickCapturePanel = p
        }
        NSApp.activate(ignoringOtherApps: true)
        quickCapturePanel?.center()
        quickCapturePanel?.makeKeyAndOrderFront(nil)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let add = NSMenuItem(title: "Quick Task…", action: #selector(openAddTaskPanel), keyEquivalent: "a")
        add.keyEquivalentModifierMask = [.command, .option]
        add.target = self
        menu.addItem(add)
        let capture = NSMenuItem(title: "Quick Capture…", action: #selector(openQuickCapturePanel), keyEquivalent: "c")
        capture.keyEquivalentModifierMask = [.command, .option]
        capture.target = self
        menu.addItem(capture)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Arthur Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func openAddTaskPanel() { showAddTaskPanel() }
    @objc private func openQuickCapturePanel() { showQuickCapturePanel() }
}
