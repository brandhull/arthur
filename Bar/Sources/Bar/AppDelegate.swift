import AppKit
import SwiftUI
import ArthurKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var panel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "ArthurBar"
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Arthur Quick Add")
        }
        statusItem.menu = buildMenu()

        // ⌥⌘A by default — distinct from craft-quick-capture's ⌥⌘Space so both
        // menu bar apps can run side by side without a shortcut collision.
        hotKey = HotKey(keyCode: 0, modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            self?.togglePanel()
        }
    }

    private func togglePanel() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        showPanel()
    }

    private func showPanel() {
        if panel == nil {
            let view = QuickAddView(onSubmit: { [weak self] in self?.panel?.orderOut(nil) })
            let hosting = NSHostingController(rootView: view)
            let p = NSPanel(contentViewController: hosting)
            p.styleMask = [.titled, .closable, .nonactivatingPanel]
            p.title = "Add to Arthur"
            p.isFloatingPanel = true
            p.level = .floating
            p.setContentSize(NSSize(width: 380, height: 200))
            panel = p
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let add = NSMenuItem(title: "Quick Add…", action: #selector(openPanel), keyEquivalent: "a")
        add.keyEquivalentModifierMask = [.command, .option]
        add.target = self
        menu.addItem(add)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Arthur Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func openPanel() { showPanel() }
}
