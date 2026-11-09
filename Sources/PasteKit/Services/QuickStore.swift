import Foundation

/// Persisted quick-snippet folders and records. Kept separate from clipboard history so the
/// monitor's hot path never touches this data.
@MainActor
final class QuickStore {
    private(set) var folders: [QuickFolder] = []
    private(set) var snippets: [QuickSnippet] = []

    private let fileURL: URL
    private let fileManager = FileManager.default

    private struct PersistedQuickData: Codable {
        var version: Int
        var folders: [QuickFolder]
        var snippets: [QuickSnippet]
    }

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("quick.json")
        load()
    }

    func addFolder(named rawName: String) -> QuickFolder? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        guard !folders.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            return nil
        }
        let folder = QuickFolder(name: name)
        folders.append(folder)
        folders.sort { $0.createdAt < $1.createdAt }
        save()
        return folder
    }

    func renameFolder(id: UUID, to rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let index = folders.firstIndex(where: { $0.id == id }),
              !folders.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame })
        else { return false }
        folders[index].name = name
        save()
        return true
    }

    func deleteFolder(id: UUID) {
        folders.removeAll { $0.id == id }
        for index in snippets.indices where snippets[index].folderID == id {
            snippets[index].folderID = nil
            snippets[index].updatedAt = Date()
        }
        save()
    }

    @discardableResult
    func addSnippet(folderID: UUID?, content: String, note: String) -> QuickSnippet? {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return nil }
        let snippet = QuickSnippet(
            folderID: folderID,
            content: content,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        snippets.append(snippet)
        snippets.sort { $0.updatedAt > $1.updatedAt }
        save()
        return snippet
    }

    func updateSnippet(
        id: UUID,
        folderID: UUID?,
        content: String,
        note: String
    ) -> QuickSnippet? {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty,
              let index = snippets.firstIndex(where: { $0.id == id }) else { return nil }
        snippets[index].folderID = folderID
        snippets[index].content = content
        snippets[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        snippets[index].updatedAt = Date()
        let updated = snippets[index]
        snippets.sort { $0.updatedAt > $1.updatedAt }
        save()
        return updated
    }

    func deleteSnippet(id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    // MARK: - Disk

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let persisted = try? JSONDecoder().decode(PersistedQuickData.self, from: data)
        else { return }
        folders = persisted.folders.sorted { $0.createdAt < $1.createdAt }
        snippets = persisted.snippets.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func save() {
        let payload = PersistedQuickData(version: 1, folders: folders, snippets: snippets)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
