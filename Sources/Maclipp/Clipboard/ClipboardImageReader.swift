import AppKit

enum ClipboardImageReader {
    static func image(from pasteboard: NSPasteboard) -> NSImage? {
        let supportedTypes = Set(NSImage.imageTypes)
        for type in pasteboard.types ?? [] where supportedTypes.contains(type.rawValue) {
            if let data = pasteboard.data(forType: type),
               let image = image(data: data, declaredType: type) {
                return image
            }
        }

        if let image = pasteboard.readObjects(
            forClasses: [NSImage.self],
            options: nil
        )?.first as? NSImage,
           ClipboardSecurityPolicy.acceptsImage(image) {
            return image
        }

        if let image = NSImage(pasteboard: pasteboard),
           ClipboardSecurityPolicy.acceptsImage(image) {
            return image
        }

        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: fileOptions
        ) as? [URL]

        return image(at: fileURLs ?? [])
    }

    static func image(data: Data, declaredType: NSPasteboard.PasteboardType) -> NSImage? {
        guard NSImage.imageTypes.contains(declaredType.rawValue) else { return nil }
        guard ClipboardSecurityPolicy.acceptsEncodedImageData(data) else { return nil }
        guard let image = NSImage(data: data),
              ClipboardSecurityPolicy.acceptsImage(image) else {
            return nil
        }
        return image
    }

    static func image(at fileURLs: [URL]) -> NSImage? {
        fileURLs.lazy.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
            ]),
            values.isRegularFile == true,
            let fileSize = values.fileSize,
            fileSize <= ClipboardSecurityPolicy.maximumImageBytes,
            let image = NSImage(contentsOf: url),
            ClipboardSecurityPolicy.acceptsImage(image) else {
                return nil
            }
            return image
        }.first
    }
}
