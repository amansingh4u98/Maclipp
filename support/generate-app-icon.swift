import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: generate-app-icon.swift <source.svg> <output.icns>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("Could not load app icon SVG at \(sourceURL.path)\n", stderr)
    exit(1)
}

let masterPNG = try renderPNG(sourceImage, pixels: 1_024)
guard let masterImage = NSImage(data: masterPNG) else {
    fputs("Could not create the master app icon image\n", stderr)
    exit(1)
}

let representations: [(type: String, pixels: Int)] = [
    ("ic11", 32),
    ("ic12", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic13", 256),
    ("ic09", 512),
    ("ic14", 512),
    ("ic10", 1_024),
]

var chunks = Data()
for representation in representations {
    let pngData = representation.pixels == 1_024
        ? masterPNG
        : try renderPNG(masterImage, pixels: representation.pixels)
    chunks.append(fourCharacterCode(representation.type))
    chunks.append(bigEndianUInt32(UInt32(pngData.count + 8)))
    chunks.append(pngData)
}

var icns = Data("icns".utf8)
icns.append(bigEndianUInt32(UInt32(chunks.count + 8)))
icns.append(chunks)
try icns.write(to: outputURL, options: .atomic)

func renderPNG(_ image: NSImage, pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw IconGenerationError.couldNotCreateBitmap
    }

    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        NSGraphicsContext.restoreGraphicsState()
        throw IconGenerationError.couldNotCreateGraphicsContext
    }

    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconGenerationError.couldNotEncodePNG
    }
    return data
}

func fourCharacterCode(_ value: String) -> Data {
    precondition(value.utf8.count == 4)
    return Data(value.utf8)
}

func bigEndianUInt32(_ value: UInt32) -> Data {
    var bigEndian = value.bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}

enum IconGenerationError: Error {
    case couldNotCreateBitmap
    case couldNotCreateGraphicsContext
    case couldNotEncodePNG
}
