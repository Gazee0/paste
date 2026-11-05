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
    @Published private(set) var isPreviewOpen = false
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

    var onPreviewChanged: ((Bool) -> Void)?
    var onPinChanged: ((Bool) -> Void)?
    var onHideRequested: (() -> Void)?
    var onShowLargeImagePreview: ((ClipboardItem, NSImage) -> Void)?

    private let imageCache = NSCache<NSString, NSImage>()
    private var toastTask: Task<Void, Never>?
    private var pendingToastAction: (() -> Void)?

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
        self.items = store.items
        self.selectedID = store.items.first?.id
        self.isWindowPinned = UserDefaults.standard.bool(forKey: AppStorageKey.windowPinned)
        self.imageCache.countLimit = 24
        self.imageCache.totalCostLimit = 64 * 1024 * 1024
        monitor.onCapture = { [weak self] payload in
            self?.capture(payload)
        }
    }

    func startMonitoring() {
        monitor.start()
    }

    // MARK: - Derived state

    var filteredItems: [ClipboardItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { $0.matches(query) }
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
    var visibleCheckedItems: [ClipboardItem] { filteredItems.filter { checkedIDs.contains($0.id) } }

    func isChecked(_ id: ClipboardItem.ID) -> Bool { checkedIDs.contains(id) }
    func isSelected(_ id: ClipboardItem.ID) -> Bool { selectedID == id }
    func shortcutIndex(for item: ClipboardItem) -> Int? {
        guard let index = filteredItems.firstIndex(where: { $0.id == item.id }), index < 9 else { return nil }
        return index + 1
    }

    func timeText(for date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? Self.timeFormatter.string(from: date)
            : Self.dayFormatter.string(from: date)
    }

    func image(for item: ClipboardItem) -> NSImage? {
        guard item.kind == .image, let name = item.imageFile else { return nil }
        if let cached = imageCache.object(forKey: name as NSString) { return cached }
        guard let data = store.imageData(for: item), let image = NSImage(data: data) else { return nil }
        imageCache.setObject(image, forKey: name as NSString, cost: data.count)
        return image
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

    func moveSelection(by delta: Int) {
        guard !isEditingPreview else { return }
        let rows = filteredItems
        guard !rows.isEmpty else { return }
        if let selectedID, let index = rows.firstIndex(where: { $0.id == selectedID }) {
            let next = min(max(index + delta, 0), rows.count - 1)
            self.selectedID = rows[next].id
        } else {
            self.selectedID = delta >= 0 ? rows.first?.id : rows.last?.id
        }
        keyboardScrollNonce += 1
    }

    /// Picks the first visible row, called when the panel is freshly presented.
    func resetSelectionToFirstRow() {
        selectedID = filteredItems.first?.id
        keyboardScrollNonce += 1
    }

    private func syncSelectionAfterFilterChange() {
        let rows = filteredItems
        if let selectedID, rows.contains(where: { $0.id == selectedID }) {
            keyboardScrollNonce += 1
            return
        }
        selectedID = rows.first?.id
        keyboardScrollNonce += 1
    }

    // MARK: - Preview and window chrome

    func togglePreview() {
        guard selectedItem != nil else { return }
        if isPreviewOpen {
            closePreview()
        } else {
            isPreviewOpen = true
            onPreviewChanged?(true)
            refocusSearch()
        }
    }

    func closePreview() {
        if editingID != nil {
            editingID = nil
        }
        guard isPreviewOpen else { return }
        isPreviewOpen = false
        onPreviewChanged?(false)
        refocusSearch()
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
        if isPreviewOpen {
            isPreviewOpen = false
            onPreviewChanged?(false)
        }
        editingID = nil
        isMultiSelecting = false
        checkedIDs.removeAll()
        searchQuery = ""
        items = store.items
        selectedID = filteredItems.first?.id
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
        guard let selectedItem else { return }
        copy(selectedItem)
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

        let outcome = PasteTarget.paste(rememberedSource: item.sourceApp)
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
        refocusSearch()
    }

    func pasteSelected() {
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
