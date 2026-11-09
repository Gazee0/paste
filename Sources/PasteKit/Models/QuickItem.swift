import Foundation

/// A user-created folder for quick snippets. The "全部" and "未分类" entries are virtual and
/// are not stored here.
struct QuickFolder: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

/// One reusable quick-paste record.
struct QuickSnippet: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    /// nil means 未分类.
    var folderID: UUID?
    var content: String
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        folderID: UUID? = nil,
        content: String,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.folderID = folderID
        self.content = content
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Sidebar selection for the quick tab.
enum QuickFolderSelection: Equatable, Hashable {
    case all
    case uncategorized
    case folder(UUID)

    var folderID: UUID? {
        if case .folder(let id) = self { return id }
        return nil
    }
}

/// Two top-level modes of the palette.
enum PaletteTab: String, CaseIterable, Identifiable {
    case clipboard
    case quick

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clipboard: return "剪贴板"
        case .quick: return "快贴"
        }
    }
}

/// Editable draft used by the quick-snippet sheet.
struct QuickEditorDraft: Identifiable, Equatable {
    let id = UUID()
    var snippetID: UUID?
    var content: String
    var note: String
    var folderID: UUID?

    var isNew: Bool { snippetID == nil }
}
