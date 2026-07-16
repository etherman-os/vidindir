import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift generate_icon.swift <iconset-directory>\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

struct IconVariant {
    let filename: String
    let pixels: Int
}

let variants = [
    IconVariant(filename: "icon_16x16.png", pixels: 16),
    IconVariant(filename: "icon_16x16@2x.png", pixels: 32),
    IconVariant(filename: "icon_32x32.png", pixels: 32),
    IconVariant(filename: "icon_32x32@2x.png", pixels: 64),
    IconVariant(filename: "icon_128x128.png", pixels: 128),
    IconVariant(filename: "icon_128x128@2x.png", pixels: 256),
    IconVariant(filename: "icon_256x256.png", pixels: 256),
    IconVariant(filename: "icon_256x256@2x.png", pixels: 512),
    IconVariant(filename: "icon_512x512.png", pixels: 512),
    IconVariant(filename: "icon_512x512@2x.png", pixels: 1024),
]

func scaled(_ value: CGFloat, for size: CGFloat) -> CGFloat {
    value * size / 1024
}

func renderIcon(pixels: Int) throws -> Data {
    let size = CGFloat(pixels)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "VidindirIcon", code: 1)
    }

    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        NSGraphicsContext.restoreGraphicsState()
        throw NSError(domain: "VidindirIcon", code: 2)
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let tileRect = NSRect(
        x: scaled(72, for: size),
        y: scaled(72, for: size),
        width: scaled(880, for: size),
        height: scaled(880, for: size)
    )
    let tile = NSBezierPath(
        roundedRect: tileRect,
        xRadius: scaled(220, for: size),
        yRadius: scaled(220, for: size)
    )
    let background = NSGradient(
        starting: NSColor(red: 0.98, green: 0.97, blue: 0.93, alpha: 1),
        ending: NSColor(red: 0.89, green: 0.94, blue: 0.91, alpha: 1)
    )!
    background.draw(in: tile, angle: -38)

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSColor(red: 0.31, green: 0.56, blue: 0.55, alpha: 0.12).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: scaled(545, for: size),
        y: scaled(500, for: size),
        width: scaled(480, for: size),
        height: scaled(480, for: size)
    )).fill()
    NSGraphicsContext.restoreGraphicsState()

    let ink = NSColor(red: 0.12, green: 0.28, blue: 0.27, alpha: 1)
    let accent = NSColor(red: 0.31, green: 0.56, blue: 0.55, alpha: 1)

    let arrow = NSBezierPath()
    arrow.lineWidth = max(2, scaled(72, for: size))
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: scaled(512, for: size), y: scaled(744, for: size)))
    arrow.line(to: NSPoint(x: scaled(512, for: size), y: scaled(430, for: size)))
    arrow.move(to: NSPoint(x: scaled(368, for: size), y: scaled(542, for: size)))
    arrow.line(to: NSPoint(x: scaled(512, for: size), y: scaled(398, for: size)))
    arrow.line(to: NSPoint(x: scaled(656, for: size), y: scaled(542, for: size)))
    accent.setStroke()
    arrow.stroke()

    let shore = NSBezierPath()
    shore.lineWidth = max(1.5, scaled(34, for: size))
    shore.lineCapStyle = .round
    shore.move(to: NSPoint(x: scaled(252, for: size), y: scaled(292, for: size)))
    shore.curve(
        to: NSPoint(x: scaled(772, for: size), y: scaled(292, for: size)),
        controlPoint1: NSPoint(x: scaled(360, for: size), y: scaled(372, for: size)),
        controlPoint2: NSPoint(x: scaled(454, for: size), y: scaled(214, for: size))
    )
    ink.setStroke()
    shore.stroke()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "VidindirIcon", code: 3)
    }
    return png
}

for variant in variants {
    let data = try renderIcon(pixels: variant.pixels)
    try data.write(to: outputDirectory.appendingPathComponent(variant.filename), options: .atomic)
}
