import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var panelController: PanelController?
    private var statusBar: StatusBarController?
    private var keyboardRouter: KeyboardRouter?
    private var imagePreviewController: ImagePreviewController?

    private let monitor = ClipboardMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        PasteTarget.startObserving()

        let store: HistoryStore
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["PASTE_DATA_DIR"], !override.isEmpty {
            store = HistoryStore(directory: URL(fileURLWithPath: override, isDirectory: true))
        } else {
            store = HistoryStore()
        }
        #else
        store = HistoryStore()
        #endif
        let model = AppModel(store: store, monitor: monitor)
        self.model = model

        let panelController = PanelController(model: model)
        self.panelController = panelController

        let imagePreviewController = ImagePreviewController(parentPanel: panelController.panel) { [weak self] in
            self?.panelController?.panel.makeKeyAndOrderFront(nil)
            self?.model?.refocusSearch()
        }
        self.imagePreviewController = imagePreviewController
        model.onShowLargeImagePreview = { [weak imagePreviewController] item, image in
            imagePreviewController?.show(item: item, image: image)
        }

        statusBar = StatusBarController(
            onOpen: { [weak self] in self?.panelController?.toggle() },
            onAccessibility: { PasteTarget.openAccessibilitySettings() },
            onQuit: { NSApp.terminate(nil) }
        )

        _ = GlobalHotKeyCenter.shared.register { [weak self] in
            self?.panelController?.toggle()
        }
        keyboardRouter = KeyboardRouter(model: model, panel: panelController.panel)

        model.startMonitoring()
        #if DEBUG
        if ProcessInfo.processInfo.environment["PASTE_DISABLE_MONITOR"] == "1" {
            monitor.stop()
        }
        #endif
        panelController.present(prepare: true)

        #if DEBUG
        runDebugUIAutomation(model: model)
        #endif
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Recover from a missed Carbon hot-key release and retry a transient registration
        // failure (for example while another app briefly owns the shortcut).
        GlobalHotKeyCenter.shared.resetPressState()
        GlobalHotKeyCenter.shared.retryRegistrationIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKeyCenter.shared.unregister()
        monitor.stop()
        imagePreviewController?.close(restoringFocus: false)
        panelController?.persistNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            panelController?.present(prepare: true)
        }
        return true
    }

    // MARK: - Main menu

    /// An accessory app has no visible menu bar, but a main menu still supplies the standard
    /// ⌘Z/⌘C/⌘V/⌘A key equivalents the search field and preview editor rely on.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Paste")
        appMenu.addItem(withTitle: "关于 Paste", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Paste", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Paste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        let close = windowMenu.addItem(withTitle: "关闭面板", action: #selector(closePanel), keyEquivalent: "w")
        close.target = self
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func closePanel() {
        panelController?.hide()
    }

    #if DEBUG
    /// Test/screenshot hook used only by debug builds. It lets the UI be exercised in a
    /// headless CI session without Accessibility-driven synthetic clicks.
    private func runDebugUIAutomation(model: AppModel) {
        guard let mode = ProcessInfo.processInfo.environment["PASTE_DEBUG_UI"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            switch mode {
            case "preview":
                if let item = model.items.first(where: { $0.kind == .text && $0.text == "account/update" })
                    ?? model.items.first(where: { $0.kind == .text }) {
                    model.select(item)
                }
                model.togglePreview()
            case "preview-delayed":
                if let item = model.items.first(where: { $0.kind == .text }) {
                    model.select(item)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    model.togglePreview()
                }
            case "preview-image":
                if let item = model.items.first(where: { $0.kind == .image }) {
                    model.select(item)
                }
                model.togglePreview()
            case "viewer":
                if let item = model.items.first(where: { $0.kind == .image }) {
                    model.select(item)
                }
                model.showLargeImagePreview()
            case "edit":
                if let item = model.items.first(where: { $0.kind == .text }) {
                    model.select(item)
                    model.togglePreview()
                    model.beginEditing()
                }
            case "multi":
                model.toggleMultiSelect()
                for item in model.items.prefix(2) {
                    model.toggleChecked(item)
                }
            case "search":
                model.searchQuery = "account"
                if let item = model.filteredItems.first { model.select(item) }
            case "quick":
                model.setActiveTab(.quick)
            case "quick-preview":
                model.setActiveTab(.quick)
                model.togglePreview()
            case "quick-edit":
                model.setActiveTab(.quick)
                model.beginNewQuickSnippet()
            case "quick-folders":
                model.setActiveTab(.quick)
                model.setQuickFocusZone(.folders)
            default:
                break
            }
        }
    }
    #endif
}
