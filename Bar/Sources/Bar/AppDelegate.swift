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
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "ArthurBar"
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "brain.fill", accessibilityDescription: "Arthur Quick Task")
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
                NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            )
        }
        statusItem.menu = buildMenu()

        // Loaded from disk (BarHotKeys), not hardcoded — reintroduced after
        // being fixed at ⌥⌘A/⌥⌘C with no way to change them. Distinct
        // defaults from craft-quick-capture's ⌥⌘Space so both menu bar apps
        // can run side by side without a shortcut collision; each hotkey
        // still gets its own separate popup rather than folding into one
        // with a mode switch — Brandon uses both regularly, each focused on
        // one job.
        let saved = BarHotKeys.load()
        if !applyAddTaskHotKey(saved.addTask, persist: false) {
            NSLog("ArthurBar: failed to register \(saved.addTask.display) for Quick Task (another app may own it)")
        }
        if !applyQuickCaptureHotKey(saved.quickCapture, persist: false) {
            NSLog("ArthurBar: failed to register \(saved.quickCapture.display) for Quick Capture (another app may own it)")
        }
    }

    /// Registers `spec` as Quick Task's global hotkey; on success persists
    /// it (unless `persist` is false, used at launch when re-applying what's
    /// already saved) and refreshes the menu's displayed shortcut. Keeps the
    /// old hotkey if registration fails, so a "someone else owns this combo"
    /// failure doesn't leave the panel with no hotkey at all.
    @discardableResult
    private func applyAddTaskHotKey(_ spec: HotKeySpec, persist: Bool = true) -> Bool {
        let old = addTaskHotKey
        addTaskHotKey = nil
        guard let new = HotKey(keyCode: spec.keyCode, modifiers: spec.modifiers,
                               callback: { [weak self] in self?.toggleAddTaskPanel() })
        else {
            addTaskHotKey = old
            return false
        }
        addTaskHotKey = new
        if persist {
            var keys = BarHotKeys.load()
            keys.addTask = spec
            keys.save()
        }
        statusItem.menu = buildMenu()
        return true
    }

    @discardableResult
    private func applyQuickCaptureHotKey(_ spec: HotKeySpec, persist: Bool = true) -> Bool {
        let old = quickCaptureHotKey
        quickCaptureHotKey = nil
        guard let new = HotKey(keyCode: spec.keyCode, modifiers: spec.modifiers,
                               callback: { [weak self] in self?.toggleQuickCapturePanel() })
        else {
            quickCaptureHotKey = old
            return false
        }
        quickCaptureHotKey = new
        if persist {
            var keys = BarHotKeys.load()
            keys.quickCapture = spec
            keys.save()
        }
        statusItem.menu = buildMenu()
        return true
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
        if let addTaskPanel { centerOnMainScreen(addTaskPanel) }
        NSApp.activate(ignoringOtherApps: true)
        addTaskPanel?.makeKeyAndOrderFront(nil)
    }

    /// `NSWindow.center()` deliberately biases the window slightly *above*
    /// true vertical center (Apple's classic "visually balanced" placement)
    /// — Brandon flagged both panels as sitting noticeably higher than he
    /// wanted. This computes the actual screen-center origin instead.
    /// `layoutIfNeeded()` first forces the panel to adopt its real size
    /// (via NSHostingController's sizingOptions) before reading `frame.size`,
    /// so a panel that hasn't been shown yet still centers correctly rather
    /// than off whatever stale/default size it started with.
    ///
    /// Centers on whichever screen currently has the mouse cursor, not
    /// `NSScreen.main` — on a multi-monitor setup `.main` tracks the screen
    /// with the key window, but this app is a background accessory with no
    /// window ever key, so `.main` doesn't reliably track wherever Brandon
    /// is actually looking/working when he presses the hotkey. That's what
    /// made the panel feel like it opened in "an odd location": it could
    /// center on a display he wasn't even looking at.
    private func centerOnMainScreen(_ panel: NSPanel) {
        panel.layoutIfNeeded()
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let screen else {
            panel.center()
            return
        }
        let screenFrame = screen.visibleFrame
        let size = panel.frame.size
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.midY - size.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
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
            // Same reasoning as showAddTaskPanel's hosting.sizingOptions —
            // QuickCaptureBarView's own .fixedSize(...) now reports a real,
            // variable height (the Destination section collapses/expands),
            // so the panel needs to track that instead of a size fixed at
            // creation time.
            hosting.sizingOptions = [.preferredContentSize]
            let p = NSPanel(contentViewController: hosting)
            p.styleMask = [.titled, .closable, .nonactivatingPanel]
            p.title = "Quick Capture"
            p.isFloatingPanel = true
            p.level = .floating
            quickCapturePanel = p
        }
        if let quickCapturePanel { centerOnMainScreen(quickCapturePanel) }
        NSApp.activate(ignoringOtherApps: true)
        quickCapturePanel?.makeKeyAndOrderFront(nil)
    }

    /// ArthurBar has no window-based main menu of its own — it's a status-
    /// item-only accessory app, `statusItem.menu` is the only NSMenu it ever
    /// builds, and `NSApp.mainMenu` was never set. That's exactly why Cmd+V
    /// (and Cmd+C/X/A) silently did nothing in the Quick Task/Quick Capture
    /// panels: macOS's key-equivalent dispatch for Cut/Copy/Paste/Select All
    /// is wired through the app's Edit menu items (even though they're never
    /// clicked) — no main menu means no Edit menu means those key
    /// equivalents never resolve to the standard `paste:`/`copy:`/etc.
    /// responder-chain actions, regardless of which text control has focus.
    /// A minimal, invisible-to-the-user main menu (this app has no Dock
    /// icon or app switcher entry, so this menu is never actually seen)
    /// with standard nil-targeted Edit items is the fix — nil target routes
    /// each action to whatever's first responder at the time, which is
    /// exactly the focused text field/view in whichever panel is open.
    private func installEditMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let keys = BarHotKeys.load()

        let add = NSMenuItem(title: "Quick Task…", action: #selector(openAddTaskPanel), keyEquivalent: keys.addTask.keyChar)
        add.keyEquivalentModifierMask = keys.addTask.cocoaModifiers
        add.target = self
        menu.addItem(add)

        let capture = NSMenuItem(title: "Quick Capture…", action: #selector(openQuickCapturePanel), keyEquivalent: keys.quickCapture.keyChar)
        capture.keyEquivalentModifierMask = keys.quickCapture.cocoaModifiers
        capture.target = self
        menu.addItem(capture)

        menu.addItem(.separator())
        let hotkeys = NSMenuItem(title: "Hotkeys…", action: #selector(openSettings), keyEquivalent: "")
        hotkeys.target = self
        menu.addItem(hotkeys)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Arthur Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func openAddTaskPanel() { showAddTaskPanel() }
    @objc private func openQuickCapturePanel() { showQuickCapturePanel() }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = BarSettingsView(hotKeys: BarHotKeys.load()) { [weak self] row, spec in
                guard let self else { return false }
                switch row {
                case .addTask: return self.applyAddTaskHotKey(spec)
                case .quickCapture: return self.applyQuickCaptureHotKey(spec)
                }
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable]
            window.title = "ArthurBar Hotkeys"
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
