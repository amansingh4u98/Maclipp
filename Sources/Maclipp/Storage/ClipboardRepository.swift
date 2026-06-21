import AppKit
import CryptoKit
import Foundation

@MainActor
final class ClipboardRepository: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var lastError: String?

    private let maximumItems: Int
    private let rootURL: URL
    private let imagesURL: URL
    private let indexURL: URL
    private let imageCache = NSCache<NSString, NSImage>()

    init(rootURL: URL? = nil, maximumItems: Int = 100) {
        self.maximumItems = maximumItems

        let defaultRoot = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Maclipp", isDirectory: true)

        self.rootURL = rootURL ?? defaultRoot
        imagesURL = self.rootURL.appendingPathComponent("Images", isDirectory: true)
        indexURL = self.rootURL.appendingPathComponent("history.json")

        prepareStorage()
        load()
    }

    func recordText(_ text: String, sourceApplication: String?) {
        guard ClipboardSecurityPolicy.acceptsText(text) else {
            lastError = "Maclipp skipped text larger than 1 MiB."
            return
        }

        let data = Data(text.utf8)
        let hash = hash(for: data)

        insertOrRefresh(
            ClipboardItem(
                id: UUID(),
                kind: .text,
                text: text,
                imageFilename: nil,
                contentHash: hash,
                sourceApplication: sourceApplication,
                createdAt: Date(),
                isPinned: false
            )
        )
    }

    func recordImage(_ image: NSImage, sourceApplication: String?) {
        guard ClipboardSecurityPolicy.acceptsImage(image) else {
            lastError = "Maclipp skipped an image larger than 50 megapixels."
            return
        }

        guard let pngData = image.pngData else {
            lastError = "Maclipp could not convert the copied image to PNG."
            return
        }
        guard ClipboardSecurityPolicy.acceptsEncodedImageData(pngData) else {
            lastError = "Maclipp skipped an image larger than 20 MiB."
            return
        }

        let contentHash = hash(for: pngData)
        if let existing = items.first(where: { $0.contentHash == contentHash }) {
            refresh(existing, sourceApplication: sourceApplication)
            return
        }

        let filename = "\(UUID().uuidString).png"
        do {
            let imageURL = imagesURL.appendingPathComponent(filename)
            try writePrivateData(pngData, to: imageURL)
            insertOrRefresh(
                ClipboardItem(
                    id: UUID(),
                    kind: .image,
                    text: nil,
                    imageFilename: filename,
                    contentHash: contentHash,
                    sourceApplication: sourceApplication,
                    createdAt: Date(),
                    isPinned: false
                )
            )
        } catch {
            lastError = "Maclipp could not store the copied image: \(error.localizedDescription)"
        }
    }

    func image(for item: ClipboardItem) -> NSImage? {
        guard let filename = item.imageFilename else { return nil }
        let cacheKey = filename as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }
        guard let imageURL = validatedImageURL(for: item),
              let image = NSImage(contentsOf: imageURL) else { return nil }
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        sortItems()
        persist()
    }

    func delete(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let removed = items.remove(at: index)
        deleteImageIfNeeded(for: removed)
        persist()
    }

    func clearUnpinned() {
        let removed = items.filter { !$0.isPinned }
        items.removeAll { !$0.isPinned }
        removed.forEach(deleteImageIfNeeded)
        persist()
    }

    private func insertOrRefresh(_ item: ClipboardItem) {
        if let existing = items.first(where: { $0.contentHash == item.contentHash }) {
            refresh(existing, sourceApplication: item.sourceApplication)
            return
        }

        items.insert(item, at: 0)
        enforceRetentionLimit()
        sortItems()
        persist()
    }

    private func refresh(_ existing: ClipboardItem, sourceApplication: String?) {
        guard let index = items.firstIndex(where: { $0.id == existing.id }) else { return }
        var refreshed = items.remove(at: index)
        refreshed.createdAt = Date()
        refreshed.sourceApplication = sourceApplication
        items.insert(refreshed, at: 0)
        sortItems()
        persist()
    }

    private func enforceRetentionLimit() {
        while items.count > maximumItems {
            let removalIndex = items.lastIndex(where: { !$0.isPinned }) ?? (items.count - 1)
            let removed = items.remove(at: removalIndex)
            deleteImageIfNeeded(for: removed)
        }
    }

    private func sortItems() {
        items.sort {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned
            }
            return $0.createdAt > $1.createdAt
        }
    }

    private func prepareStorage() {
        do {
            try FileManager.default.createDirectory(
                at: imagesURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try setPrivateDirectoryPermissions(at: rootURL)
            try setPrivateDirectoryPermissions(at: imagesURL)
            try migrateStoredFilePermissions()
        } catch {
            lastError = "Maclipp could not prepare local storage: \(error.localizedDescription)"
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return }

        do {
            let data = try Data(contentsOf: indexURL)
            items = try JSONDecoder.maclipp.decode([ClipboardItem].self, from: data)
            sortItems()
            enforceRetentionLimit()
            persist()
        } catch {
            lastError = "Maclipp could not load clipboard history: \(error.localizedDescription)"
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder.maclipp.encode(items)
            try writePrivateData(data, to: indexURL)
            lastError = nil
        } catch {
            lastError = "Maclipp could not save clipboard history: \(error.localizedDescription)"
        }
    }

    private func deleteImageIfNeeded(for item: ClipboardItem) {
        if let filename = item.imageFilename {
            imageCache.removeObject(forKey: filename as NSString)
        }
        guard let imageURL = validatedImageURL(for: item) else { return }
        try? FileManager.default.removeItem(at: imageURL)
    }

    private func hash(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func writePrivateData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private func setPrivateDirectoryPermissions(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
    }

    private func migrateStoredFilePermissions() throws {
        if FileManager.default.fileExists(atPath: indexURL.path) {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: indexURL.path
            )
        }

        let imageFiles = try FileManager.default.contentsOfDirectory(
            at: imagesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        for imageFile in imageFiles {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: imageFile.path
            )
        }
    }

    private func validatedImageURL(for item: ClipboardItem) -> URL? {
        guard let filename = item.imageFilename,
              filename.hasSuffix(".png"),
              UUID(uuidString: String(filename.dropLast(4))) != nil,
              filename == URL(fileURLWithPath: filename).lastPathComponent else {
            return nil
        }

        let candidate = imagesURL.appendingPathComponent(filename).standardizedFileURL
        let imagesRoot = imagesURL.standardizedFileURL.path + "/"
        guard candidate.path.hasPrefix(imagesRoot) else { return nil }
        return candidate
    }
}

private extension JSONEncoder {
    static let maclipp: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let maclipp: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension NSImage {
    var pngData: Data? {
        if let tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffRepresentation),
           let data = bitmap.representation(using: .png, properties: [:]) {
            return data
        }

        var imageRect = NSRect(origin: .zero, size: size)
        guard let cgImage = cgImage(
            forProposedRect: &imageRect,
            context: nil,
            hints: nil
        ) else {
            return nil
        }

        return NSBitmapImageRep(cgImage: cgImage)
            .representation(using: .png, properties: [:])
    }
}
