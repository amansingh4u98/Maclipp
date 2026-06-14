import AppKit
import Foundation

@main
struct RepositoryChecks {
    @MainActor
    static func main() {
        duplicateTextIsRefreshedInsteadOfDuplicated()
        retentionEnforcesTotalLimitAndPrefersPinnedItems()
        searchMatchesTextAndSourceApplication()
        readsJPEGClipboardData()
        readsCopiedImageFile()
        keyboardShortcutPersistsAndDisplays()
        sensitivePasteboardMarkersAreSkipped()
        oversizedPayloadsAreRejected()
        storageUsesOwnerOnlyPermissions()
        invalidStoredImagePathsAreRejected()
        print("Repository checks passed")
    }

    @MainActor
    private static func duplicateTextIsRefreshedInsteadOfDuplicated() {
        withRepository { repository in
            repository.recordText("first", sourceApplication: "Notes")
            repository.recordText("second", sourceApplication: "Safari")
            repository.recordText("first", sourceApplication: "Terminal")

            check(repository.items.count == 2, "duplicate text should not create a third item")
            check(repository.items.first?.text == "first", "refreshed text should move to the front")
            check(
                repository.items.first?.sourceApplication == "Terminal",
                "refreshed text should update its source application"
            )
        }
    }

    @MainActor
    private static func retentionEnforcesTotalLimitAndPrefersPinnedItems() {
        withRepository(maximumItems: 2) { repository in
            repository.recordText("keep", sourceApplication: nil)
            repository.togglePin(repository.items[0])
            repository.recordText("old", sourceApplication: nil)
            repository.recordText("new", sourceApplication: nil)

            check(repository.items.count == 2, "retention should enforce the total item limit")
            check(
                repository.items.contains(where: { $0.text == "keep" && $0.isPinned }),
                "retention should preserve pinned items when an unpinned item can be removed"
            )
            check(
                repository.items.contains(where: { $0.text == "new" }),
                "retention should preserve the newest unpinned item"
            )
        }
    }

    private static func searchMatchesTextAndSourceApplication() {
        let item = ClipboardItem(
            id: UUID(),
            kind: .text,
            text: "A useful snippet",
            imageFilename: nil,
            contentHash: "hash",
            sourceApplication: "Xcode",
            createdAt: Date(),
            isPinned: false
        )

        check(item.matches("snippet"), "search should match clip text")
        check(item.matches("xcode"), "search should match source application")
        check(!item.matches("missing"), "search should reject unrelated terms")
    }

    private static func readsJPEGClipboardData() {
        let image = makeTestImage()
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [:]) else {
            fatalError("Could not create JPEG fixture")
        }

        let captured = ClipboardImageReader.image(
            data: jpegData,
            declaredType: .init("public.jpeg")
        )

        check(captured != nil, "clipboard reader should decode JPEG-only pasteboards")
    }

    private static func readsCopiedImageFile() {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        guard let tiffData = makeTestImage().tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Could not create PNG fixture")
        }
        try? pngData.write(to: temporaryURL)

        let captured = ClipboardImageReader.image(at: [temporaryURL])
        check(captured != nil, "clipboard reader should load copied image files")
    }

    private static func makeTestImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        return image
    }

    private static func keyboardShortcutPersistsAndDisplays() {
        let shortcut = KeyboardShortcut.default
        let data = try? JSONEncoder().encode(shortcut)
        let decoded = data.flatMap { try? JSONDecoder().decode(KeyboardShortcut.self, from: $0) }

        check(decoded == shortcut, "keyboard shortcuts should round-trip through persistence")
        check(shortcut.displayName == "⌥Space", "the default shortcut should display as Option+Space")
    }

    private static func sensitivePasteboardMarkersAreSkipped() {
        let sensitiveTypes = [
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.TransientType",
            "org.nspasteboard.AutoGeneratedType",
        ]

        for rawType in sensitiveTypes {
            let types: [NSPasteboard.PasteboardType] = [.string, .init(rawType)]
            check(
                !ClipboardSecurityPolicy.shouldCapture(types: types),
                "sensitive pasteboard type \(rawType) should be skipped"
            )
        }
        check(
            ClipboardSecurityPolicy.shouldCapture(types: [.string]),
            "ordinary text pasteboards should remain eligible"
        )
    }

    @MainActor
    private static func oversizedPayloadsAreRejected() {
        withRepository { repository in
            let oversizedText = String(
                repeating: "a",
                count: ClipboardSecurityPolicy.maximumTextBytes + 1
            )
            repository.recordText(oversizedText, sourceApplication: nil)

            check(repository.items.isEmpty, "oversized text should not be stored")
            check(repository.lastError != nil, "oversized text should report a local error")
        }

        let oversizedImageData = Data(
            count: ClipboardSecurityPolicy.maximumImageBytes + 1
        )
        check(
            !ClipboardSecurityPolicy.acceptsEncodedImageData(oversizedImageData),
            "oversized encoded image data should be rejected"
        )
    }

    @MainActor
    private static func storageUsesOwnerOnlyPermissions() {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let repository = ClipboardRepository(rootURL: temporaryURL)
        repository.recordText("private", sourceApplication: nil)
        repository.recordImage(makeTestImage(), sourceApplication: nil)

        let imagesURL = temporaryURL.appendingPathComponent("Images", isDirectory: true)
        let indexURL = temporaryURL.appendingPathComponent("history.json")
        let imageURL = try? FileManager.default.contentsOfDirectory(
            at: imagesURL,
            includingPropertiesForKeys: nil
        ).first
        check(posixPermissions(at: temporaryURL) == 0o700, "storage root should use 0700")
        check(posixPermissions(at: imagesURL) == 0o700, "images directory should use 0700")
        check(posixPermissions(at: indexURL) == 0o600, "history index should use 0600")
        check(
            imageURL.flatMap(posixPermissions) == 0o600,
            "stored images should use 0600"
        )
    }

    private static func posixPermissions(at url: URL) -> Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.posixPermissions] as? Int
    }

    @MainActor
    private static func invalidStoredImagePathsAreRejected() {
        withRepository { repository in
            let invalidItem = ClipboardItem(
                id: UUID(),
                kind: .image,
                text: nil,
                imageFilename: "../outside.png",
                contentHash: "invalid-path",
                sourceApplication: nil,
                createdAt: Date(),
                isPinned: false
            )

            check(repository.image(for: invalidItem) == nil, "invalid image paths should be rejected")
        }
    }

    @MainActor
    private static func withRepository(
        maximumItems: Int = 100,
        body: (ClipboardRepository) -> Void
    ) {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        body(
            ClipboardRepository(
                rootURL: temporaryURL,
                maximumItems: maximumItems
            )
        )
    }

    private static func check(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fatalError("Check failed: \(message)")
        }
    }
}
