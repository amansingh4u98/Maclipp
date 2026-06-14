import AppKit

@MainActor
enum ClipboardWriter {
    static func restore(_ item: ClipboardItem, from repository: ClipboardRepository) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            guard let text = item.text else { return false }
            return pasteboard.setString(text, forType: .string)
        case .image:
            guard let image = repository.image(for: item) else { return false }
            return pasteboard.writeObjects([image])
        }
    }
}
