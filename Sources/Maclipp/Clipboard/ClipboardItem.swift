import Foundation

struct ClipboardItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case text
        case image
    }

    let id: UUID
    let kind: Kind
    var text: String?
    var imageFilename: String?
    let contentHash: String
    var sourceApplication: String?
    var createdAt: Date
    var isPinned: Bool

    var displayTitle: String {
        switch kind {
        case .text:
            let firstLine = text?
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init) ?? "Empty text"
            return firstLine.isEmpty ? "Empty text" : firstLine
        case .image:
            return "Image"
        }
    }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return displayTitle.localizedCaseInsensitiveContains(query)
            || (text?.localizedCaseInsensitiveContains(query) ?? false)
            || (sourceApplication?.localizedCaseInsensitiveContains(query) ?? false)
    }
}
