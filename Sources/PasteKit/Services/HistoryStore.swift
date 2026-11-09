import AppKit
import Foundation
import os

/// Persisted, deduplicated clipboard history.
///
/// The store is deliberately UI-free so it can be tested with a temporary directory. All
/// mutations happen on the main actor; the history is small once image bytes have been moved
/// out to the Images directory.
@MainActor
final class HistoryStore {
    private(set) var items: [ClipboardItem] = []

    let directory: URL
    let maxItems: Int

    var onError: ((String) -> Void)?

    private let historyURL: URL
    private let imagesDirectory: URL
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.edy.paste", category: "HistoryStore")
    private let imageCache = NSCache<NSString, NSData>()

    private struct PersistedHistory: Codable {
        var version: Int
        var items: [ClipboardItem]
    }

    init(directory: URL? = nil, maxItems: Int = 200, load: Bool = true) {
        let root = directory ?? Self.defaultDirectory()
        self.directory = root
        self.maxItems = maxItems
        self.historyURL = root.appendingPathComponent("history.json")
        self.imagesDirectory = root.appendingPathComponent("Images", isDirectory: true)

        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        imageCache.countLimit = 8
        imageCache.totalCostLimit = 16 * 1024 * 1024

        if load {
            loadFromDisk()
        }
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Paste", isDirectory: true)
    }

    // MARK: - Capture

    /// Adds captured content. When the same content is already present its timestamp is
    /// refreshed and it moves to the top; the existing id, pin state and annotation survive.
    @discardableResult
    func add(_ payload: ClipboardPayload, at date: Date = Date()) -> ClipboardItem? {
        let hash = payload.contentHash

        if let existingIndex = items.firstIndex(where: { $0.contentHash == hash }) {
            var existing = items[existingIndex]
            existing.createdAt = date
            if let source = payload.sourceApp, !source.isEmpty {
                existing.sourceApp = source
            }
            // If more than one copy somehow exists, collapse it as well.
            let duplicates = items.indices.filter { $0 != existingIndex && items[$0].contentHash == hash }
            if !duplicates.isEmpty {
                removeImageFiles(at: duplicates)
                for index in duplicates.reversed() { items.remove(at: index) }
            }
            if let currentIndex = items.firstIndex(where: { $0.id == existing.id }) {
                items[currentIndex] = existing
            } else {
                items.append(existing)
            }
            sortNewestFirst()
            save()
            return existing
        }

        var item = ClipboardItem(
            kind: payload.kind,
            text: payload.kind == .text ? payload.text : nil,
            pixelWidth: payload.pixelWidth,
            pixelHeight: payload.pixelHeight,
            filePaths: payload.filePaths,
            rtfData: payload.rtfData,
            htmlData: payload.htmlData,
            createdAt: date,
            sourceApp: payload.sourceApp,
            contentHash: hash,
            byteCount: payload.byteCount
        )

        if payload.kind == .image {
            guard let data = payload.imageData, !data.isEmpty else { return nil }
            let fileName = "\(item.id.uuidString).png"
            guard writeImage(data, named: fileName) else {
                logger.error("Could not write image for clipboard item")
                return nil
            }
            item.imageFile = fileName
            imageCache.setObject(data as NSData, forKey: fileName as NSString, cost: data.count)
        }

        items.append(item)
        sortNewestFirst()
        pruneIfNeeded()
        save()
        return item
    }

    // MARK: - Query

    func item(withID id: ClipboardItem.ID) -> ClipboardItem? {
        items.first { $0.id == id }
    }

    func imageData(for item: ClipboardItem) -> Data? {
        guard item.kind == .image, let name = item.imageFile else { return nil }
        if let cached = imageCache.object(forKey: name as NSString) {
            return cached as Data
        }
        let url = imagesDirectory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        imageCache.setObject(data as NSData, forKey: name as NSString, cost: data.count)
        return data
    }

    // MARK: - Mutation

    func delete(ids: Set<ClipboardItem.ID>) {
        guard !ids.isEmpty else { return }
        let indexes = items.indices.filter { ids.contains(items[$0].id) }
        guard !indexes.isEmpty else { return }
        removeImageFiles(at: indexes)
        items.removeAll { ids.contains($0.id) }
        save()
    }

    func delete(_ id: ClipboardItem.ID) {
        delete(ids: [id])
    }

    func clearUnpinned() {
        let indexes = items.indices.filter { !items[$0].isPinned }
        guard !indexes.isEmpty else { return }
        removeImageFiles(at: indexes)
        items.removeAll { !$0.isPinned }
        save()
    }

    func togglePin(_ id: ClipboardItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        save()
    }

    /// Replaces the plain-text body of a text entry. Rich representations are dropped because
    /// the user just edited the plain text.
    @discardableResult
    func updateText(_ id: ClipboardItem.ID, text: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].kind == .text else {
            return false
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }

        let hash = ClipboardItem.hash(text: text)
        if let duplicate = items.firstIndex(where: { $0.id != id && $0.contentHash == hash }) {
            let duplicateIDs: Set<ClipboardItem.ID> = [items[duplicate].id]
            delete(ids: duplicateIDs)
        }
        guard let currentIndex = items.firstIndex(where: { $0.id == id }) else { return false }

        items[currentIndex].text = text
        items[currentIndex].rtfData = nil
        items[currentIndex].htmlData = nil
        items[currentIndex].contentHash = hash
        items[currentIndex].byteCount = text.utf8.count
        sortNewestFirst()
        save()
        return true
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard fileManager.fileExists(atPath: historyURL.path) else { return }
        do {
            let data = try Data(contentsOf: historyURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let stored: [ClipboardItem]
            if let history = try? decoder.decode(PersistedHistory.self, from: data) {
                stored = history.items
            } else {
                stored = try decoder.decode([ClipboardItem].self, from: data)
            }
            items = stored
            sortNewestFirst()
            if items.count > maxItems {
                pruneIfNeeded()
                save()
            }
        } catch {
            logger.error("History load failed: \(error.localizedDescription, privacy: .public)")
            onError?("历史记录读取失败，将从空记录开始。")
            items = []
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(PersistedHistory(version: 1, items: items))
            try data.write(to: historyURL, options: .atomic)
        } catch {
            logger.error("History save failed: \(error.localizedDescription, privacy: .public)")
            onError?("历史记录保存失败。")
        }
    }

    private func sortNewestFirst() {
        items.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString > $1.id.uuidString
        }
    }

    /// Drops the oldest unpinned entries beyond the limit. Pinned entries never count against
    /// the rolling cap.
    private func pruneIfNeeded() {
        guard items.count > maxItems else { return }
        var doomed: [Int] = []
        var remaining = items.count
        for index in items.indices.reversed() {
            guard remaining > maxItems else { break }
            guard !items[index].isPinned else { continue }
            doomed.append(index)
            remaining -= 1
        }
        guard !doomed.isEmpty else { return }
        removeImageFiles(at: doomed)
        for index in doomed.sorted(by: >) { items.remove(at: index) }
    }

    // MARK: - Images

    private func writeImage(_ data: Data, named name: String) -> Bool {
        do {
            try data.write(to: imagesDirectory.appendingPathComponent(name), options: .atomic)
            return true
        } catch {
            logger.error("Image write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func removeImageFiles(at indexes: [Int]) {
        for index in indexes {
            guard let name = items[index].imageFile else { continue }
            try? fileManager.removeItem(at: imagesDirectory.appendingPathComponent(name))
            imageCache.removeObject(forKey: name as NSString)
        }
    }
}
