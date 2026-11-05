#!/usr/bin/env swift
//
// Generates Resources/AppIcon.icns for Paste.
//
// The artwork is drawn fully in code so the icon can be regenerated on any Mac without design
// tools: a rounded gradient tile with a white clipboard glyph. Every iconset size is rendered as
// vector artwork rather than by downscaling a single 1024 bitmap, and stroke widths are clamped to
// a minimum device-pixel size so the 16pt/32pt variants stay legible.
//
// Usage:
//   swift Scripts/make_icon.swift [output.icns]
//
// The default output is Resources/AppIcon.icns relative to the current working directory.

import AppKit
import Foundation

// MARK: - Configuration

let canvas: CGFloat = 1024
let defaultOutput = "Resources/AppIcon.icns"

/// (iconset file name, pixel size) — the exact set `iconutil` expects for `AppIcon.iconset`.
let iconsetEntries: [(name: String, pixelSize: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

// MARK: - Helpers

func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make_icon: error: \(message)\n".utf8))
    exit(1)
}

func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fail("\(executable) exited with status \(process.terminationStatus)")
    }
}

// MARK: - Artwork

/// Draws the icon in a 1024×1024 coordinate space. `deviceScale` is pixels per artwork unit, used
/// to keep thin strokes visible at small sizes.
func drawArtwork(deviceScale: CGFloat) {
    // Minimum stroke in device pixels, converted back to artwork units.
    func clampedStroke(_ base: CGFloat, minimumPixels: CGFloat) -> CGFloat {
        max(base, minimumPixels / deviceScale)
    }

    // Rounded tile with the standard macOS "squircle-ish" radius, inset from the canvas.
    let tileInset: CGFloat = 62
    let tileRect = NSRect(
        x: tileInset,
        y: tileInset,
        width: canvas - tileInset * 2,
        height: canvas - tileInset * 2
    )
    let tileRadius = tileRect.width * 0.2237
    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: tileRadius, yRadius: tileRadius)

    // Soft drop shadow so the tile lifts off a light or dark wallpaper.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = srgb(0x0B1020, alpha: 0.32)
    shadow.shadowBlurRadius = 26
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    srgb(0x1A2140).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Indigo → violet gradient, top to bottom.
    let gradient = NSGradient(
        colorsAndLocations:
        (srgb(0x5B8DEF), 0.0),
        (srgb(0x6A6BF5), 0.55),
        (srgb(0x8A5CF6), 1.0)
    )!
    gradient.draw(in: tilePath, angle: -90)

    // Subtle top-left highlight for depth.
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    let highlight = NSGradient(
        colors: [NSColor.white.withAlphaComponent(0.20), NSColor.white.withAlphaComponent(0.0)]
    )!
    highlight.draw(
        in: NSRect(x: tileRect.minX, y: tileRect.midY, width: tileRect.width, height: tileRect.height / 2),
        angle: -90
    )
    NSGraphicsContext.restoreGraphicsState()

    // Hairline rim.
    NSGraphicsContext.saveGraphicsState()
    NSColor.white.withAlphaComponent(0.16).setStroke()
    let rim = NSBezierPath(roundedRect: tileRect.insetBy(dx: 1.5, dy: 1.5), xRadius: tileRadius, yRadius: tileRadius)
    rim.lineWidth = max(2, 1.0 / deviceScale)
    rim.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // MARK: Clipboard glyph (white)

    let bodyWidth: CGFloat = 400
    let bodyHeight: CGFloat = 486
    let bodyRect = NSRect(
        x: (canvas - bodyWidth) / 2,
        y: (canvas - bodyHeight) / 2 - 8,
        width: bodyWidth,
        height: bodyHeight
    )
    let bodyRadius: CGFloat = 58
    let bodyOutline = NSBezierPath(
        roundedRect: bodyRect,
        xRadius: bodyRadius,
        yRadius: bodyRadius
    )
    let bodyStroke = clampedStroke(38, minimumPixels: 1.15)
    bodyOutline.lineWidth = bodyStroke
    bodyOutline.lineJoinStyle = .round

    NSGraphicsContext.saveGraphicsState()
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = srgb(0x1B1B45, alpha: 0.24)
    glyphShadow.shadowBlurRadius = 12
    glyphShadow.shadowOffset = NSSize(width: 0, height: -4)
    glyphShadow.set()
    NSColor.white.setStroke()
    bodyOutline.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // Three ruled lines inside the board.
    let lineColor = NSColor.white.withAlphaComponent(0.92)
    let lineHeight = clampedStroke(28, minimumPixels: 0.9)
    let lineYs: [CGFloat] = [bodyRect.midY + 82, bodyRect.midY, bodyRect.midY - 82]
    let lineWidths: [CGFloat] = [212, 212, 144]
    for (y, width) in zip(lineYs, lineWidths) {
        let lineRect = NSRect(
            x: (canvas - width) / 2,
            y: y - lineHeight / 2,
            width: width,
            height: lineHeight
        )
        let line = NSBezierPath(roundedRect: lineRect, xRadius: lineHeight / 2, yRadius: lineHeight / 2)
        lineColor.setFill()
        line.fill()
    }

    // Clipboard clip straddling the top edge.
    let clipWidth: CGFloat = 160
    let clipHeight = clampedStroke(76, minimumPixels: 1.0)
    let clipRect = NSRect(
        x: (canvas - clipWidth) / 2,
        y: bodyRect.maxY - clipHeight / 2,
        width: clipWidth,
        height: clipHeight
    )
    let clip = NSBezierPath(roundedRect: clipRect, xRadius: clipHeight / 2.4, yRadius: clipHeight / 2.4)
    NSColor.white.setFill()
    clip.fill()

    // Small notch in the clip so it reads as a clipboard fastener at larger sizes.
    if deviceScale >= 0.5 {
        let notch = NSBezierPath(
            roundedRect: clipRect.insetBy(dx: clipWidth * 0.36, dy: clipHeight * 0.3),
            xRadius: clipHeight * 0.2,
            yRadius: clipHeight * 0.2
        )
        srgb(0x6A6BF5, alpha: 0.9).setFill()
        notch.fill()
    }
}

/// Renders one square PNG bitmap of `pixelSize` pixels.
func renderPNG(pixelSize: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fail("could not allocate a \(pixelSize)px bitmap")
    }

    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))

    let scale = CGFloat(pixelSize) / canvas
    context.cgContext.scaleBy(x: scale, y: scale)
    drawArtwork(deviceScale: scale)

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fail("PNG encoding failed for \(pixelSize)px")
    }
    return png
}

// MARK: - Main

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultOutput
let outputURL = URL(fileURLWithPath: outputPath)
let fileManager = FileManager.default

let workDirectory = fileManager.temporaryDirectory
    .appendingPathComponent("PasteAppIcon-\(UUID().uuidString)", isDirectory: true)
let iconsetURL = workDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: workDirectory) }

// Render each unique pixel size once and reuse it for the @1x/@2x pairs.
var rendered: [Int: Data] = [:]
for size in Set(iconsetEntries.map { $0.pixelSize }).sorted() {
    rendered[size] = renderPNG(pixelSize: size)
}
for entry in iconsetEntries {
    guard let data = rendered[entry.pixelSize] else { fail("missing render for \(entry.pixelSize)px") }
    try data.write(to: iconsetURL.appendingPathComponent("\(entry.name).png"), options: .atomic)
}

let parentURL = outputURL.deletingLastPathComponent()
try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

let iconutil = "/usr/bin/iconutil"
guard fileManager.isExecutableFile(atPath: iconutil) else { fail("iconutil not found at \(iconutil)") }
try run(iconutil, ["-c", "icns", iconsetURL.path, "-o", outputURL.path])

guard fileManager.fileExists(atPath: outputURL.path) else { fail("iconutil produced no output") }
let attributes = try? fileManager.attributesOfItem(atPath: outputURL.path)
let byteCount = (attributes?[.size] as? Int) ?? 0
print("make_icon: wrote \(outputURL.path) (\(byteCount) bytes, \(iconsetEntries.count) representations)")
