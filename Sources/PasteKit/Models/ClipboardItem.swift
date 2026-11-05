import CryptoKit
import Foundation

/// The three kinds of clipboard content Paste keeps.
enum ClipboardKind: String, Codable, Sendable {
    case text
    case image
    case files

    var systemImage: String {
        switch self {
        case .text: return "doc.text"
        case .image: return "photo"
        case .files: return "folder"
        }
    }

    var label: String {
        switch self {
        case .text: return "文本"
        case .image: return "图片"
        case .files: return "文件"
        }
    }
}

/// One clipboard history entry.
///
/// Text and file paths live in the JSON history file. Image bytes live on disk in
/// `Images/<imageFile>` so a history full of screenshots does not turn into a huge JSON blob.
struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var kind: ClipboardKind
    /// Plain text for `.text`; nil for images and files.
    var text: String?
    /// File name inside the store's Images directory, for `.image`.
    var imageFile: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
    /// Absolute paths for `.files`.
    var filePaths: [String]
    /// Optional rich representations preserved from the source pasteboard.
    var rtfData: Data?
    var htmlData: Data?
    var createdAt: Date
    var isPinned: Bool
    var sourceApp: String?
    /// Stable digest of the copied content, used to collapse duplicates.
    var contentHash: String
    var byteCount: Int

    init(
        id: UUID = UUID(),
        kind: ClipboardKind,
        text: String? = nil,
        imageFile: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        filePaths: [String] = [],
        rtfData: Data? = nil,
        htmlData: Data? = nil,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        sourceApp: String? = nil,
        contentHash: String = "",
        byteCount: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageFile = imageFile
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.filePaths = filePaths
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.sourceApp = sourceApp
        self.contentHash = contentHash
        self.byteCount = byteCount
    }

    /// Permissive decoding: a history file from an older build should never cost the user
    /// their whole history because a new optional field appeared.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(ClipboardKind.self, forKey: .kind) ?? .text
        text = try c.decodeIfPresent(String.self, forKey: .text)
        imageFile = try c.decodeIfPresent(String.self, forKey: .imageFile)
        pixelWidth = try c.decodeIfPresent(Int.self, forKey: .pixelWidth)
        pixelHeight = try c.decodeIfPresent(Int.self, forKey: .pixelHeight)
        filePaths = try c.decodeIfPresent([String].self, forKey: .filePaths) ?? []
        rtfData = try c.decodeIfPresent(Data.self, forKey: .rtfData)
        htmlData = try c.decodeIfPresent(Data.self, forKey: .htmlData)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        sourceApp = try c.decodeIfPresent(String.self, forKey: .sourceApp)
        contentHash = try c.decodeIfPresent(String.self, forKey: .contentHash) ?? ""
        byteCount = try c.decodeIfPresent(Int.self, forKey: .byteCount) ?? 0
    }

    // MARK: - Presentation

    /// One or two lines shown in the history row.
    var displayText: String {
        switch kind {
        case .text:
            let body = text ?? ""
            return body.count > 20_000 ? String(body.prefix(20_000)) + "…" : body
        case .image:
            if let w = pixelWidth, let h = pixelHeight {
                return "图片 · \(w)×\(h)"
            }
            return "图片"
        case .files:
            let names = filePaths.map { URL(fileURLWithPath: $0).lastPathComponent }
            guard let first = names.first else { return "文件" }
            return names.count == 1 ? first : "\(first) 等 \(names.count) 个文件"
        }
    }

    /// Short metadata for the preview footer.
    var detailText: String {
        switch kind {
        case .text:
            return "\(text?.count ?? 0) 字符"
        case .image:
            if let w = pixelWidth, let h = pixelHeight { return "\(w)×\(h)" }
            return "图片"
        case .files:
            return "\(filePaths.count) 个文件"
        }
    }

    /// Everything a search can reasonably match.
    var searchText: String {
        var parts: [String] = [kind.label]
        if let text { parts.append(text) }
        if let sourceApp { parts.append(sourceApp) }
        parts.append(contentsOf: filePaths)
        parts.append(contentsOf: filePaths.map { URL(fileURLWithPath: $0).lastPathComponent })
        if let w = pixelWidth, let h = pixelHeight { parts.append("\(w)x\(h) \(w)×\(h)") }
        return parts.joined(separator: "\n")
    }

    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return searchText.localizedCaseInsensitiveContains(trimmed)
    }

    var fileURLs: [URL] {
        kind == .files ? filePaths.map { URL(fileURLWithPath: $0) } : []
    }

    // MARK: - Hashing

    static func hash(text: String) -> String {
        hashed(Data(text.utf8), prefix: "text")
    }

    static func hash(filePaths: [String]) -> String {
        hashed(Data(filePaths.joined(separator: "\u{0}").utf8), prefix: "files")
    }

    static func hash(imageData: Data) -> String {
        hashed(imageData, prefix: "image")
    }

    private static func hashed(_ data: Data, prefix: String) -> String {
        var digest = SHA256()
        digest.update(data: Data(prefix.utf8))
        digest.update(data: Data([0]))
        digest.update(data: data)
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
