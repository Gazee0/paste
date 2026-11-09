import AppKit
import Combine
import Foundation

/// Everything the SwiftUI surface needs: filtered history, selection, preview, multi-select,
/// editing, toasts, and the copy/paste actions.
@MainActor
final class AppModel: ObservableObject {
    // MARK: - Published state

    @Published private(set) var items: [ClipboardItem] = []
    @Published var searchQuery: String = "" {
        didSet {
            guard oldValue != searchQuery else { return }
            syncSelectionAfterFilterChange()
        }
    }
    @Published private(set) var selectedID: ClipboardItem.ID?
    @Published private(set) var historyFilter: HistoryFilter = .all
    @Published private(set) var activeTab: PaletteTab = .clipboard

    // MARK: Quick snippets
    @Published private(set) var quickFolders: [QuickFolder] = []
    @Published private(set) var quickSnippets: [QuickSnippet] = []
    @Published private(set) var selectedQuickID: QuickSnippet.ID?
    @Published private(set) var quickFolderSelection: QuickFolderSelection = .all
    @Published private(set) var quickFocusZone: QuickFocusZone = .list
    @Published var quickEditorDraft: QuickEditorDraft?
    @Published private(set) var isPreviewOpen = false
    /// Whether the preview column is still on screen. It stays true through the closing
    /// animation, so the window can shrink before the list claims the freed width.
    @Published private(set) var isPreviewVisible = false
    /// True while the window is resizing for the preview. Hover selection is suppressed during
    /// this time because the window moves underneath a stationary pointer, which would otherwise
    /// select several rows in quick succession while the animation is running.
    @Published private(set) var isPreviewTransitioning = false
    @Published private(set) var isWindowPinned: Bool
    @Published private(set) var isMultiSelecting = false
    @Published private(set) var checkedIDs: Set<ClipboardItem.ID> = []
    @Published private(set) var editingID: ClipboardItem.ID?
    @Published private(set) var toast: ToastMessage?
    /// Bumped by keyboard navigation so the list can scroll the new selection into view
    /// without doing the same thing (and jumping under the pointer) on every hover.
    @Published private(set) var keyboardScrollNonce = 0
    /// Bumped whenever the search field should take focus.
    @Published private(set) var focusRequestNonce = 0

    // MARK: - Dependencies

    let store: HistoryStore
    let monitor: ClipboardMonitor
    private let quickStore: QuickStore

    var onPreviewChanged: ((Bool) -> Void)?
    var onPinChanged: ((Bool) -> Void)?
    var onHideRequested: (() -> Void)?
    var onShowLargeImagePreview: ((ClipboardItem, NSImage) -> Void)?

    private let previewImageCache = NSCache<NSString, NSImage>()
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private var toastTask: Task<Void, Never>?
    private var pendingToastAction: (() -> Void)?
    private var previewTransitionGeneration = 0

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "M/d"
        return formatter
    }()

    init(store: HistoryStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
        self.quickStore = QuickStore(directory: store.directory)
        self.items = store.items
        self.selectedID = store.items.first?.id
        self.quickFolders = quickStore.folders
        self.quickSnippets = quickStore.snippets
        self.selectedQuickID = quickStore.snippets.first?.id
        self.isWindowPinned = UserDefaults.standard.bool(forKey: AppStorageKey.windowPinned)
        // Full-size decoded images are never cached: the large-image viewer owns the image for
        // its lifetime, so closing the viewer releases it. List rows use small downsampled
        // thumbnails from `thumbnailCache`.
        self.previewImageCache.countLimit = 1
        self.previewImageCache.totalCostLimit = 8 * 1024 * 1024
        self.thumbnailCache.countLimit = 48
        self.thumbnailCache.totalCostLimit = 8 * 1024 * 1024
        monitor.onCapture = { [weak self] payload in
            self?.capture(payload)
        }
    }

    func startMonitoring() {
        monitor.start()
    }

    // MARK: - Derived state

    var filteredItems: [ClipboardItem] {
        let filteredByKind: [ClipboardItem]
        if let kind = historyFilter.kind {
            filteredByKind = items.filter { $0.kind == kind }
        } else {
            filteredByKind = items
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return filteredByKind }
        return filteredByKind.filter { $0.matches(query) }
    }

    var quickFilteredSnippets: [QuickSnippet] {
        let base: [QuickSnippet]
        switch quickFolderSelection {
        case .all:
            base = quickSnippets
        case .uncategorized:
            base = quickSnippets.filter { $0.folderID == nil }
        case .folder(let folderID):
            base = quickSnippets.filter { $0.folderID == folderID }
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.content.localizedCaseInsensitiveContains(query)
                || $0.note.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedQuickSnippet: QuickSnippet? {
        guard let selectedQuickID else { return nil }
        return quickSnippets.first { $0.id == selectedQuickID }
    }

    var quickFolderChoices: [QuickFolderSelection] {
        [.all, .uncategorized] + quickFolders.map { .folder($0.id) }
    }

    func quickFolderTitle(for selection: QuickFolderSelection) -> String {
        switch selection {
        case .all: return "全部"
        case .uncategorized: return "未分类"
        case .folder(let id):
            return quickFolders.first(where: { $0.id == id })?.name ?? "未分类"
        }
    }

    func quickFolderTitle(for snippet: QuickSnippet) -> String {
        guard let folderID = snippet.folderID else { return "未分类" }
        return quickFolders.first(where: { $0.id == folderID })?.name ?? "未分类"
    }

    var currentSelectionExists: Bool {
        activeTab == .clipboard ? selectedItem != nil : selectedQuickSnippet != nil
    }

    var selectedItem: ClipboardItem? {
        guard let selectedID else { return nil }
        return items.first { $0.id == selectedID }
    }

    var previewItem: ClipboardItem? {
        selectedItem
    }

    var editingItem: ClipboardItem? {
        guard let editingID else { return nil }
        return items.first { $0.id == editingID }
    }

    var isEditingPreview: Bool { editingID != nil }
    var historyCount: Int { items.count }
    var unpinnedCount: Int { items.filter { !$0.isPinned }.count }
    var checkedCount: Int { checkedIDs.count }
    var hasItems: Bool { !items.isEmpty }
    var isSearching: Bool { !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isFiltering: Bool { isSearching || historyFilter != .all }
    var visibleCheckedItems: [ClipboardItem] { filteredItems.filter { checkedIDs.contains($0.id) } }

    func isChecked(_ id: ClipboardItem.ID) -> Bool { checkedIDs.contains(id) }
    func isSelected(_ id: ClipboardItem.ID) -> Bool { selectedID == id }
    func shortcutIndex(for item: ClipboardItem) -> Int? {
        guard let index = filteredItems.firstIndex(where: { $0.id == item.id }), index < 9 else { return nil }
        return index + 1
    }

    func quickShortcutIndex(for snippet: QuickSnippet) -> Int? {
        guard let index = quickFilteredSnippets.firstIndex(where: { $0.id == snippet.id }), index < 9 else {
            return nil
        }
        return index + 1
    }

    func timeText(for date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? Self.timeFormatter.string(from: date)
            : Self.dayFormatter.string(from: date)
    }

    /// Full-resolution image for the large-image viewer only. Deliberately uncached: the
    /// viewer is the sole owner, so closing it releases the decoded image.
    func image(for item: ClipboardItem) -> NSImage? {
        guard item.kind == .image, item.imageFile != nil else { return nil }
        guard let data = store.imageData(for: item) else { return nil }
        return NSImage(data: data)
    }

    /// Downsampled image for the preview pane. The preview only needs roughly 2× its 284pt
    /// width; the full-resolution image is reserved for the large-image viewer.
    func previewImage(for item: ClipboardItem) -> NSImage? {
        guard item.kind == .image, let name = item.imageFile else { return nil }
        let key = name as NSString
        if let cached = previewImageCache.object(forKey: key) { return cached }
        guard let data = store.imageData(for: item),
              let image = Self.downsampledImage(data: data, maxPixelSize: 640) else { return nil }
        previewImageCache.setObject(image, forKey: key, cost: data.count)
        return image
    }

    /// Small decoded image for a history row. Never decode the full image for a row: a 1920px
    /// screenshot can cost several megabytes after ImageIO decoding even if the PNG is small.
    func thumbnail(for item: ClipboardItem) -> NSImage? {
        guard item.kind == .image, let name = item.imageFile else { return nil }
        let key = name as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let data = store.imageData(for: item),
              let image = Self.downsampledImage(data: data, maxPixelSize: 256) else { return nil }
        thumbnailCache.setObject(image, forKey: key, cost: data.count)
        return image
    }

    /// Release decoded image memory when the palette is hidden or when the preview changes.
    func trimImageCaches() {
        previewImageCache.removeAllObjects()
        thumbnailCache.removeAllObjects()
    }

    private static func downsampledImage(data: Data, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Capture

    private func capture(_ payload: ClipboardPayload) {
        guard store.add(payload) != nil else { return }
        refreshFromStore(keepSelection: true, moveKeyboardFocus: false)
    }

    // MARK: - Selection

    func select(_ item: ClipboardItem) {
        guard !isEditingPreview else { return }
        guard selectedID != item.id else { return }
        selectedID = item.id
    }

    func selectQuick(_ snippet: QuickSnippet) {
        guard selectedQuickID != snippet.id else { return }
        selectedQuickID = snippet.id
    }

    func moveSelection(by delta: Int) {
        guard !isEditingPreview else { return }
        if activeTab == .quick {
            if quickFocusZone == .folders {
                moveQuickFolderSelection(by: delta)
                return
            }
            let rows = quickFilteredSnippets
            guard !rows.isEmpty else { return }
            if let selectedQuickID, let index = rows.firstIndex(where: { $0.id == selectedQuickID }) {
                let next = min(max(index + delta, 0), rows.count - 1)
                self.selectedQuickID = rows[next].id
            } else {
                selectedQuickID = delta >= 0 ? rows.first?.id : rows.last?.id
            }
            keyboardScrollNonce += 1
            return
        }
        let rows = filteredItems
        guard !rows.isEmpty else { return }
        if let selectedID, let index = rows.firstIndex(where: { $0.id == selectedID }) {
            let next = min(max(index + delta, 0), rows.count - 1)
            self.selectedID = rows[next].id
        } else {
            selectedID = delta >= 0 ? rows.first?.id : rows.last?.id
        }
        keyboardScrollNonce += 1
    }

    /// Picks the first visible row, called when the panel is freshly presented.
    func resetSelectionToFirstRow() {
        if activeTab == .quick {
            selectedQuickID = quickFilteredSnippets.first?.id
        } else {
            selectedID = filteredItems.first?.id
        }
        keyboardScrollNonce += 1
    }

    private func syncSelectionAfterFilterChange() {
        if activeTab == .quick {
            let rows = quickFilteredSnippets
            if let selectedQuickID, rows.contains(where: { $0.id == selectedQuickID }) {
                keyboardScrollNonce += 1
                return
            }
            selectedQuickID = rows.first?.id
            keyboardScrollNonce += 1
            return
        }
        let rows = filteredItems
        if let selectedID, rows.contains(where: { $0.id == selectedID }) {
            keyboardScrollNonce += 1
            return
        }
        selectedID = rows.first?.id
        keyboardScrollNonce += 1
    }

    func switchTab() {
        setActiveTab(activeTab == .clipboard ? .quick : .clipboard)
    }

    func setActiveTab(_ tab: PaletteTab) {
        guard tab != activeTab else {
            refocusSearch()
            return
        }
        editingID = nil
        quickEditorDraft = nil
        quickFocusZone = .list
        activeTab = tab
        searchQuery = ""
        if tab == .quick {
            selectedQuickID = quickFilteredSnippets.first?.id
        } else {
            selectedID = filteredItems.first?.id
        }
        keyboardScrollNonce += 1
        // Keep the preview's shown/hidden state across tabs. If the target tab has no
        // selection, the preview column shows its empty placeholder until one is available.
        refocusSearch()
    }

    func setQuickFolder(_ selection: QuickFolderSelection) {
        guard selection != quickFolderSelection else {
            refocusSearch()
            return
        }
        quickFolderSelection = selection
        selectedQuickID = quickFilteredSnippets.first?.id
        keyboardScrollNonce += 1
        refocusSearch()
    }

    func setQuickFocusZone(_ zone: QuickFocusZone) {
        guard zone != quickFocusZone else { return }
        quickFocusZone = zone
        refocusSearch()
    }

    private func moveQuickFolderSelection(by delta: Int) {
        let choices = quickFolderChoices
        guard !choices.isEmpty else { return }
        let currentIndex = choices.firstIndex(of: quickFolderSelection) ?? 0
        let next = min(max(currentIndex + delta, 0), choices.count - 1)
        guard next != currentIndex else { return }
        setQuickFolder(choices[next])
    }

    func cycleQuickFolder(by delta: Int) {
        let choices = quickFolderChoices
        guard !choices.isEmpty else { return }
        let index = choices.firstIndex(of: quickFolderSelection) ?? 0
        let next = (index + delta + choices.count) % choices.count
        setQuickFolder(choices[next])
    }

    func cycleHistoryFilter(by delta: Int) {
        setHistoryFilter(historyFilter.offset(by: delta))
    }

    func setHistoryFilter(_ filter: HistoryFilter) {
        guard filter != historyFilter else {
            refocusSearch()
            return
        }
        historyFilter = filter
        syncSelectionAfterFilterChange()
        refocusSearch()
    }

    // MARK: - Preview and window chrome

    func togglePreview() {
        if isPreviewOpen {
            closePreview()
            return
        }
        guard currentSelectionExists else { return }
        isPreviewOpen = true
        isPreviewVisible = true
        onPreviewChanged?(true)
        refocusSearch()
    }

    func closePreview() {
        if editingID != nil {
            editingID = nil
        }
        guard isPreviewOpen else { return }
        isPreviewOpen = false
        // Keep isPreviewVisible true until PanelController reports the shrink animation has
        // finished. Removing the preview column immediately would make the list snap to the
        // full window width while the window is still wide.
        onPreviewChanged?(false)
        refocusSearch()
    }

    @discardableResult
    func beginPreviewWindowTransition() -> Int {
        previewTransitionGeneration += 1
        isPreviewTransitioning = true
        return previewTransitionGeneration
    }

    func finishPreviewWindowTransition(generation: Int) {
        guard generation == previewTransitionGeneration else { return }
        isPreviewTransitioning = false
    }

    /// Called by the window controller when the close animation has finished.
    func finishPreviewCollapse() {
        guard !isPreviewOpen else { return }
        isPreviewVisible = false
    }

    func toggleWindowPin() {
        isWindowPinned.toggle()
        UserDefaults.standard.set(isWindowPinned, forKey: AppStorageKey.windowPinned)
        onPinChanged?(isWindowPinned)
        refocusSearch()
    }

    func requestHide() {
        onHideRequested?()
    }

    /// Called every time the panel is brought back after being hidden. The panel should open
    /// in its compact state with a clean search, ready for typing.
    func prepareForPresentation() {
        previewTransitionGeneration += 1
        isPreviewTransitioning = false
        if isPreviewOpen || isPreviewVisible {
            isPreviewOpen = false
            isPreviewVisible = false
            onPreviewChanged?(false)
        }
        editingID = nil
        quickEditorDraft = nil
        activeTab = .clipboard
        isMultiSelecting = false
        checkedIDs.removeAll()
        searchQuery = ""
        historyFilter = .all
        quickFolderSelection = .all
        quickFocusZone = .list
        items = store.items
        quickFolders = quickStore.folders
        quickSnippets = quickStore.snippets
        selectedID = filteredItems.first?.id
        selectedQuickID = quickFilteredSnippets.first?.id
        keyboardScrollNonce += 1
        dismissToast()
        refocusSearch()
    }

    func panelDidBecomeKey() {
        guard !isEditingPreview else { return }
        refocusSearch()
    }

    func refocusSearch() {
        guard !isEditingPreview else { return }
        focusRequestNonce += 1
    }

    // MARK: - Quick snippets

    var quickCountText: String {
        if isSearching {
            return "\(quickFilteredSnippets.count)/\(quickSnippets.count)"
        }
        return "\(quickSnippets.count)"
    }

    func quickCount(in selection: QuickFolderSelection) -> Int {
        switch selection {
        case .all:
            return quickSnippets.count
        case .uncategorized:
            return quickSnippets.filter { $0.folderID == nil }.count
        case .folder(let id):
            return quickSnippets.filter { $0.folderID == id }.count
        }
    }

    func beginNewQuickSnippet() {
        let folderID: UUID? = {
            if case .folder(let id) = quickFolderSelection { return id }
            return nil
        }()
        quickEditorDraft = QuickEditorDraft(
            snippetID: nil,
            content: "",
            note: "",
            folderID: folderID
        )
    }

    func beginEditingQuickSnippet(_ snippet: QuickSnippet? = nil) {
        guard let snippet = snippet ?? selectedQuickSnippet else { return }
        quickEditorDraft = QuickEditorDraft(
            snippetID: snippet.id,
            content: snippet.content,
            note: snippet.note,
            folderID: snippet.folderID
        )
    }

    func saveQuickEditor(
        snippetID: UUID?,
        folderID: UUID?,
        content: String,
        note: String
    ) {
        let saved: QuickSnippet?
        if let snippetID {
            saved = quickStore.updateSnippet(
                id: snippetID,
                folderID: folderID,
                content: content,
                note: note
            )
        } else {
            saved = quickStore.addSnippet(
                folderID: folderID,
                content: content,
                note: note
            )
        }
        guard let saved else {
            showToast("内容不能为空")
            return
        }
        if quickFolderSelection != .all {
            quickFolderSelection = saved.folderID.map { .folder($0) } ?? .uncategorized
        }
        quickEditorDraft = nil
        quickFocusZone = .list
        refreshQuick(select: saved.id)
        if isPreviewOpen {
            ensurePreviewMatchesSelection()
        }
        showToast(snippetID == nil ? "已新建快贴" : "已保存快贴")
        refocusSearch()
    }

    func cancelQuickEditor() {
        quickEditorDraft = nil
        refocusSearch()
    }

    func deleteQuickSnippet(_ snippet: QuickSnippet) {
        quickStore.deleteSnippet(id: snippet.id)
        refreshQuick(select: selectedQuickID == snippet.id ? nil : selectedQuickID)
        if activeTab == .quick && isPreviewOpen && selectedQuickSnippet == nil {
            closePreview()
        }
        showToast("已删除快贴")
        refocusSearch()
    }

    @discardableResult
    func addQuickFolder(named name: String) -> Bool {
        guard let folder = quickStore.addFolder(named: name) else {
            showToast("文件夹名为空或已存在")
            return false
        }
        refreshQuick(select: nil)
        quickFolderSelection = .folder(folder.id)
        quickFocusZone = .folders
        selectedQuickID = quickFilteredSnippets.first?.id
        keyboardScrollNonce += 1
        showToast("已新建文件夹")
        refocusSearch()
        return true
    }

    @discardableResult
    func renameQuickFolder(id: UUID, to name: String) -> Bool {
        guard quickStore.renameFolder(id: id, to: name) else {
            showToast("文件夹名为空或已存在")
            return false
        }
        refreshQuick(select: selectedQuickID)
        refocusSearch()
        return true
    }

    func deleteQuickFolder(id: UUID) {
        quickStore.deleteFolder(id: id)
        if quickFolderSelection == .folder(id) {
            quickFolderSelection = .all
        }
        refreshQuick(select: nil)
        showToast("已删除文件夹")
        refocusSearch()
    }

    private func refreshQuick(select preferredID: UUID?) {
        quickFolders = quickStore.folders
        quickSnippets = quickStore.snippets
        let rows = quickFilteredSnippets
        if let preferredID, rows.contains(where: { $0.id == preferredID }) {
            selectedQuickID = preferredID
        } else if let selectedQuickID, rows.contains(where: { $0.id == selectedQuickID }) {
            // Keep the current selection if it is still visible.
        } else {
            selectedQuickID = rows.first?.id
        }
        keyboardScrollNonce += 1
    }

    private func ensurePreviewMatchesSelection() {
        guard isPreviewOpen else { return }
        if !currentSelectionExists {
            closePreview()
        }
    }

    // MARK: - Multi-select

    func toggleMultiSelect() {
        if isEditingPreview { editingID = nil }
        isMultiSelecting.toggle()
        if !isMultiSelecting { checkedIDs.removeAll() }
        refocusSearch()
    }

    func toggleChecked(_ item: ClipboardItem) {
        guard isMultiSelecting else { return }
        if checkedIDs.contains(item.id) {
            checkedIDs.remove(item.id)
        } else {
            checkedIDs.insert(item.id)
        }
    }

    func deleteChecked() {
        guard !checkedIDs.isEmpty else { return }
        let count = checkedIDs.count
        let ids = checkedIDs
        checkedIDs.removeAll()
        store.delete(ids: ids)
        refreshFromStore(keepSelection: true, moveKeyboardFocus: false)
        if !hasItems { closePreviewIfPossible() }
        showToast("已删除 \(count) 项")
        refocusSearch()
    }

    func clearUnpinned() {
        let count = unpinnedCount
        guard count > 0 else {
            showToast("没有可清除的未固定记录")
            refocusSearch()
            return
        }
        store.clearUnpinned()
        refreshFromStore(keepSelection: true, moveKeyboardFocus: false)
        if !hasItems { closePreviewIfPossible() }
        showToast("已清除 \(count) 项未固定记录")
        refocusSearch()
    }

    // MARK: - Item actions

    func copy(_ item: ClipboardItem) {
        guard PasteboardWriter.write(item, imageData: store.imageData(for: item)) != nil else {
            showToast("拷贝失败，请重试")
            return
        }
        monitor.acknowledgeOwnWrite()
        showToast("已拷贝")
        refocusSearch()
    }

    func copySelected() {
        if activeTab == .quick {
            guard let selectedQuickSnippet else { return }
            copyQuick(selectedQuickSnippet)
            return
        }
        guard let selectedItem else { return }
        copy(selectedItem)
    }

    func copyQuick(_ snippet: QuickSnippet) {
        guard PasteboardWriter.writeText(snippet.content) != nil else {
            showToast("拷贝失败，请重试")
            return
        }
        monitor.acknowledgeOwnWrite()
        showToast("已拷贝")
        refocusSearch()
    }

    func pasteQuick(_ snippet: QuickSnippet) {
        guard PasteboardWriter.writeText(snippet.content) != nil else {
            showToast("拷贝失败，请重试")
            return
        }
        monitor.acknowledgeOwnWrite()
        let outcome = PasteTarget.paste(keepWindowVisible: isWindowPinned)
        switch outcome {
        case .pasted:
            break
        case .needsPermission:
            showToast(
                outcome.message,
                actionTitle: "打开设置",
                action: { PasteTarget.openAccessibilitySettings() }
            )
        case .noTarget, .notDelivered, .copyFailed:
            showToast(outcome.message)
        }
        if !isWindowPinned || outcome != .pasted {
            refocusSearch()
        }
    }

    /// Opens the standalone viewer for the selected image. The window itself is owned by the
    /// app shell; this model method is the UI's single entry point.
    func showLargeImagePreview() {
        guard let item = selectedItem, item.kind == .image else { return }
        guard let image = image(for: item) else {
            showToast("无法载入图片")
            return
        }
        onShowLargeImagePreview?(item, image)
    }

    func paste(_ item: ClipboardItem) {
        guard PasteboardWriter.write(item, imageData: store.imageData(for: item)) != nil else {
            showToast("拷贝失败，请重试")
            return
        }
        monitor.acknowledgeOwnWrite()

        let outcome = PasteTarget.paste(
            rememberedSource: item.sourceApp,
            keepWindowVisible: isWindowPinned
        )
        switch outcome {
        case .pasted:
            break
        case .needsPermission:
            showToast(
                outcome.message,
                actionTitle: "打开设置",
                action: { PasteTarget.openAccessibilitySettings() }
            )
        case .noTarget, .notDelivered, .copyFailed:
            showToast(outcome.message)
        }
        // When the palette is pinned and the target app comes forward, do not steal focus back
        // from it. The panel remains visible and can be clicked to focus the search again.
        if !isWindowPinned || outcome != .pasted {
            refocusSearch()
        }
    }

    func pasteSelected() {
        if activeTab == .quick {
            guard let selectedQuickSnippet else { return }
            pasteQuick(selectedQuickSnippet)
            return
        }
        guard let selectedItem, !isMultiSelecting else { return }
        paste(selectedItem)
    }

    func delete(_ item: ClipboardItem) {
        store.delete(item.id)
        refreshFromStore(keepSelection: true, moveKeyboardFocus: false)
        if !hasItems { closePreviewIfPossible() }
        showToast("已删除")
        refocusSearch()
    }

    func togglePin(_ item: ClipboardItem) {
        let willPin = !item.isPinned
        store.togglePin(item.id)
        refreshFromStore(keepSelection: true, moveKeyboardFocus: false)
        showToast(willPin ? "已固定" : "已取消固定")
        refocusSearch()
    }

    // MARK: - Editing

    func beginEditing() {
        guard let item = selectedItem, item.kind == .text else { return }
        guard !isMultiSelecting else { return }
        editingID = item.id
        // Make sure the row being edited is on screen; the editor itself steals focus, so the
        // user cannot re-find the row with the pointer while writing.
        keyboardScrollNonce += 1
    }

    func cancelEditing() {
        guard editingID != nil else { return }
        editingID = nil
        refocusSearch()
    }

    @discardableResult
    func saveEditing(text: String) -> Bool {
        guard let id = editingID else { return false }
        guard store.updateText(id, text: text) else {
            showToast("内容不能为空")
            return false
        }
        editingID = nil
        refreshFromStore(keepSelection: true, moveKeyboardFocus: false)
        showToast("已保存")
        refocusSearch()
        return true
    }

    // MARK: - Refresh

    private func refreshFromStore(keepSelection: Bool, moveKeyboardFocus: Bool) {
        items = store.items
        checkedIDs.formIntersection(Set(items.map(\.id)))
        if let editingID, !items.contains(where: { $0.id == editingID }) {
            self.editingID = nil
        }

        let rows = filteredItems
        if keepSelection, let selectedID, rows.contains(where: { $0.id == selectedID }) {
            // Leave the selection alone.
        } else {
            selectedID = rows.first?.id
        }
        if moveKeyboardFocus { keyboardScrollNonce += 1 }
    }

    private func closePreviewIfPossible() {
        guard isPreviewOpen else { return }
        editingID = nil
        isPreviewOpen = false
        onPreviewChanged?(false)
    }

    // MARK: - Toast

    func showToast(_ text: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        toastTask?.cancel()
        pendingToastAction = action
        let message = ToastMessage(text: text, actionTitle: actionTitle)
        toast = message

        let duration: UInt64 = actionTitle == nil ? 2_400_000_000 : 6_000_000_000
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: duration)
            guard !Task.isCancelled else { return }
            guard let self, self.toast?.id == message.id else { return }
            self.toast = nil
            self.pendingToastAction = nil
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toastTask = nil
        toast = nil
        pendingToastAction = nil
    }

    func performToastAction() {
        let action = pendingToastAction
        dismissToast()
        action?()
    }
}
