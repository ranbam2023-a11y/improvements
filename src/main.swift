//
//  main.swift — app bootstrap: window, menus, menu bar item.
//
//  Ran's macOS Improvements: a small collection of tweaks ("augments") to
//  macOS. Closing the window leaves the app running so the augments keep
//  working; quit from the menu bar icon or with ⌘Q.
//

import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    private var window: NSWindow?
    private var sidebar: SidebarViewController?
    private var detail: DetailViewController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        CLI.handle(model: model)
        buildMenu()
        buildWindow()
        buildStatusItem()

    }

    // Keep running after the window closes, so augments stay active.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: Window

    private func buildWindow() {
        let sidebar = SidebarViewController(model: model)
        let detail = DetailViewController(model: model)
        sidebar.onSelect = { [weak self] id in
            guard let self = self else { return }
            self.model.selection = id
            self.sidebar?.reload()
            self.detail?.show(id: id)
        }

        let split = NSSplitViewController()
        let left = NSSplitViewItem(sidebarWithViewController: sidebar)
        left.minimumThickness = 220
        left.maximumThickness = 320
        left.canCollapse = false
        let right = NSSplitViewItem(viewController: detail)
        split.addSplitViewItem(left)
        split.addSplitViewItem(right)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Ran's macOS Improvements"
        window.contentViewController = split
        window.minSize = NSSize(width: 760, height: 480)

        // Assigning contentViewController sizes the window to the split view's
        // (tiny) fitting size, and a stale autosaved frame can be collapsed too,
        // so make sure we always end up with a usable window.
        window.setFrameAutosaveName("ImprovementsMainWindow")
        if window.frame.width < 600 || window.frame.height < 400 {
            window.setContentSize(NSSize(width: 940, height: 640))
            window.center()
        }

        self.sidebar = sidebar
        self.detail = detail
        self.window = window

        sidebar.reload()
        detail.show(id: model.selection ?? "highfive")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showWindow() {
        if window == nil { buildWindow() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Menus

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Ran's macOS Improvements",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Improvements",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Improvements",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: Menu bar item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "wand.and.stars",
                                     accessibilityDescription: "Improvements")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let open = NSMenuItem(title: "Open Improvements", action: #selector(showWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        for augment in model.augments {
            let item = NSMenuItem(title: augment.name, action: #selector(toggleAugment(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = augment.id
            item.state = augment.enabled ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Improvements",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func toggleAugment(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let augment = model.augments.first(where: { $0.id == id }) else { return }
        model.setEnabled(augment, !augment.enabled)
        sidebar?.reload()
        detail?.show(id: model.selection ?? id)
    }
}

/// Headless flags, so install scripts can drive the login item.
enum CLI {
    static func handle(model: AppModel) {
        let arguments = CommandLine.arguments

        if arguments.contains("--version") {
            print("Improvements 1.0")
            exit(0)
        }

        // Fire every augment's action once, as if the gesture had happened.
        if arguments.contains("--fire") {
            model.augments.forEach { $0.fireOnce() }
            Thread.sleep(forTimeInterval: 1.5)
            exit(0)
        }

        // Parse (and optionally post) a shortcut without touching the trackpad.
        if let index = arguments.firstIndex(of: "--test-shortcut"), index + 1 < arguments.count {
            let text = arguments[index + 1]
            guard let combo = ShortcutParser.parse(text) else {
                print("could not parse \"\(text)\"")
                exit(1)
            }
            print("parsed: \(combo.display)  keyCode=\(combo.keyCode)  flags=\(combo.flags.rawValue)")
            print("accessibility permission: \(ShortcutPoster.hasPermission)")
            if arguments.contains("--post") {
                print("posted: \(ShortcutPoster.post(combo))")
            }
            exit(0)
        }
        if arguments.contains("--register-login") {
            do {
                try SMAppService.mainApp.register()
                print("login item registered")
            } catch {
                print("could not register login item: \(error.localizedDescription)")
            }
            exit(0)
        }
        if arguments.contains("--unregister-login") {
            do {
                try SMAppService.mainApp.unregister()
                print("login item removed")
            } catch {
                print("could not remove login item: \(error.localizedDescription)")
            }
            exit(0)
        }
    }
}

// MARK: - Launch

// Make any unexpected crash diagnosable: the reason lands in our own log.
NSSetUncaughtExceptionHandler { exception in
    let stack = exception.callStackSymbols.prefix(14).joined(separator: " | ")
    Log.write("UNCAUGHT \(exception.name.rawValue): \(exception.reason ?? "(no reason)") :: \(stack)")
}

let application = NSApplication.shared
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.setActivationPolicy(.regular)
application.run()
