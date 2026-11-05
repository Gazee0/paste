import Foundation

/// Kind filter shown above the history list.
enum HistoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case text
    case image
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .text: return "文本"
        case .image: return "图片"
        case .files: return "文件"
        }
    }

    var kind: ClipboardKind? {
        switch self {
        case .all: return nil
        case .text: return .text
        case .image: return .image
        case .files: return .files
        }
    }

    func offset(by delta: Int) -> HistoryFilter {
        let filters = Self.allCases
        guard let index = filters.firstIndex(of: self) else { return .all }
        let next = (index + delta + filters.count) % filters.count
        return filters[next]
    }
}
