import AppKit
import SwiftUI
import ArthurKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var clipHotKey: HotKey?
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
        if !applyClipHotKey(saved.clip, persist: false) {
            NSLog("ArthurBar: failed to register \(saved.clip.display) for Clip Selection (another app may own it)")
        }
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
    private func applyClipHotKey(_ spec: HotKeySpec, persist: Bool = true) -> Bool {
        let old = clipHotKey
        clipHotKey = nil
        guard let new = HotKey(keyCode: spec.keyCode, modifiers: spec.modifiers,
                               callback: { [weak self] in self?.clipSelection() })
        else {
            clipHotKey = old
            return false
        }
        clipHotKey = new
        if persist {
            var keys = BarHotKeys.load()
            keys.clip = spec
            keys.save()
        }
        statusItem.menu = buildMenu()
        return true
    }

    /// Grabs the selected text from the front app and appends it, as plain
    /// text, to the clip page. No window: the toast is the only feedback.
    /// Nothing selected falls back to the clipboard, which may hold text or an
    /// image. If a text save fails, the text goes onto the clipboard so it
    /// isn't lost.
    private func clipSelection() {
        guard let page = ClipStore.page else {
            Toast.shared.show("Choose a clip page in ArthurBar settings", isError: true)
            openSettings()
            return
        }
        let config = Config.load()
        guard config.isConfigured else {
            Toast.shared.show("Set up Craft in Arthur first", isError: true)
            return
        }
        Task { @MainActor in
            let grabbed = await SelectionGrabber.grab()
            if grabbed.needsPermission {
                Toast.shared.show("Allow ArthurBar in Accessibility to clip selected text", isError: true)
                return
            }
            var text = grabbed.text ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let image = ClipboardImage.data(from: .general) {
                    await clipImage(image, to: page, craftLink: config.craftLink)
                    return
                }
                text = NSPasteboard.general.string(forType: .string) ?? ""
            }
            let clip = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clip.isEmpty else {
                Toast.shared.show("Nothing selected or copied", isError: true)
                return
            }
            do {
                try await CraftClient(url: config.craftLink).appendBlocks(pageId: page.id, markdown: clip)
                ClipStore.record(text: clip, pageTitle: page.title)
                statusItem.menu = buildMenu()
                Toast.shared.show("Added to \(page.title)")
            } catch {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(clip, forType: .string)
                Toast.shared.show(isClearlyOffline(error)
                                  ? "Offline. Copied to the clipboard instead"
                                  : "Couldn't save. Copied to the clipboard instead", isError: true)
            }
        }
    }

    /// Shrinks a copied image and appends it to the clip page. The clipboard
    /// is left alone, so a failed send loses nothing.
    private func clipImage(_ original: Data, to page: ClipPage, craftLink: String) async {
        Toast.shared.show("Sending image…")
        do {
            let jpeg = try await Task.detached { try ImagePrep.jpegForCraft(original) }.value
            try await CraftClient(url: craftLink).appendImage(pageId: page.id, jpeg: jpeg)
            ClipStore.recordImage(pageTitle: page.title)
            statusItem.menu = buildMenu()
            Toast.shared.show("Image added to \(page.title)")
        } catch let failure as ImagePrep.Failure {
            let message: String
            switch failure {
            case .tooSmall: message = "Image is too small for Craft (under 100 px)"
            case .tooLarge: message = "Image is too large to send to Craft"
            case .unreadable: message = "Couldn't read the copied image"
            }
            Toast.shared.show(message, isError: true)
        } catch {
            Toast.shared.show(isClearlyOffline(error)
                              ? "Offline. The image is still on the clipboard"
                              : "Couldn't save. The image is still on the clipboard", isError: true)
        }
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

        let clip = NSMenuItem(title: "Clip Selection", action: #selector(clipFromMenu), keyEquivalent: keys.clip.keyChar)
        clip.keyEquivalentModifierMask = keys.clip.cocoaModifiers
        clip.target = self
        menu.addItem(clip)

        let recents = ClipStore.recents
        if !recents.isEmpty {
            let recentItem = NSMenuItem(title: "Recent Clips", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for r in recents {
                // An image clip has no text to copy back, so it's listed
                // but not clickable (no action).
                if r.isImage == true {
                    sub.addItem(NSMenuItem(title: "Image  →  \(r.pageTitle)", action: nil, keyEquivalent: ""))
                    continue
                }
                let flat = r.text.replacingOccurrences(of: "\n", with: " ")
                let preview = flat.count > 40 ? String(flat.prefix(40)) + "…" : flat
                let item = NSMenuItem(title: "\(preview)  →  \(r.pageTitle)", action: #selector(copyRecentClip(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = r.text
                sub.addItem(item)
            }
            recentItem.submenu = sub
            menu.addItem(recentItem)
        }
        menu.addItem(.separator())

        let add = NSMenuItem(title: "Quick Task…", action: #selector(openAddTaskPanel), keyEquivalent: keys.addTask.keyChar)
        add.keyEquivalentModifierMask = keys.addTask.cocoaModifiers
        add.target = self
        menu.addItem(add)

        let capture = NSMenuItem(title: "Quick Capture…", action: #selector(openQuickCapturePanel), keyEquivalent: keys.quickCapture.keyChar)
        capture.keyEquivalentModifierMask = keys.quickCapture.cocoaModifiers
        capture.target = self
        menu.addItem(capture)

        menu.addItem(.separator())
        let hotkeys = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        hotkeys.target = self
        menu.addItem(hotkeys)
        menu.addItem(.separator())
        let version = NSMenuItem(title: "Arthur Bar \(AppVersion.display)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(NSMenuItem(title: "Quit Arthur Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func clipFromMenu() {
        // Let the menu close and the previous app regain focus first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.clipSelection() }
    }

    @objc private func copyRecentClip(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Toast.shared.show("Copied to the clipboard")
    }

    @objc private func openAddTaskPanel() { showAddTaskPanel() }
    @objc private func openQuickCapturePanel() { showQuickCapturePanel() }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = BarSettingsView(hotKeys: BarHotKeys.load()) { [weak self] row, spec in
                guard let self else { return false }
                switch row {
                case .clip: return self.applyClipHotKey(spec)
                case .addTask: return self.applyAddTaskHotKey(spec)
                case .quickCapture: return self.applyQuickCaptureHotKey(spec)
                }
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable]
            window.title = "ArthurBar Settings"
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
