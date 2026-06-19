#!/usr/bin/env swift
import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("usage: render-dmg-background.swift <output.png> <mascot.png>\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let mascotURL = URL(fileURLWithPath: arguments[2])
let canvasSize = NSSize(width: 680, height: 420)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("failed to create DMG background bitmap\n", stderr)
    exit(1)
}

bitmap.size = canvasSize
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        red: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: 1
    )
}

func fill(_ rect: NSRect, _ fillColor: NSColor) {
    fillColor.setFill()
    NSBezierPath(rect: rect).fill()
}

func stroke(_ rect: NSRect, _ strokeColor: NSColor, width: CGFloat = 3) {
    strokeColor.setStroke()
    let path = NSBezierPath(rect: rect)
    path.lineWidth = width
    path.stroke()
}

let bounds = NSRect(origin: .zero, size: canvasSize)
NSGradient(colors: [color(0xeaf7fb), color(0xbfd8ef)])?.draw(in: bounds, angle: 90)

color(0x8ba9c8).withAlphaComponent(0.22).setStroke()
let grid = NSBezierPath()
for x in stride(from: 0, through: Int(canvasSize.width), by: 34) {
    grid.move(to: NSPoint(x: CGFloat(x), y: 0))
    grid.line(to: NSPoint(x: CGFloat(x), y: canvasSize.height))
}
for y in stride(from: 0, through: Int(canvasSize.height), by: 34) {
    grid.move(to: NSPoint(x: 0, y: CGFloat(y)))
    grid.line(to: NSPoint(x: canvasSize.width, y: CGFloat(y)))
}
grid.lineWidth = 1
grid.stroke()

let appPanel = NSRect(x: 74, y: 82, width: 176, height: 166)
let applicationsPanel = NSRect(x: 430, y: 82, width: 176, height: 166)
for panel in [appPanel, applicationsPanel] {
    fill(panel.offsetBy(dx: 7, dy: -7), color(0x061833))
    fill(panel, color(0xf7fbff))
    stroke(panel, color(0x061833), width: 4)
}

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 284, y: 168))
arrow.line(to: NSPoint(x: 386, y: 168))
arrow.lineWidth = 8
arrow.lineCapStyle = .square
color(0x061833).setStroke()
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 396, y: 168))
arrowHead.line(to: NSPoint(x: 366, y: 190))
arrowHead.line(to: NSPoint(x: 366, y: 146))
arrowHead.close()
color(0xff6b67).setFill()
arrowHead.fill()
color(0x061833).setStroke()
arrowHead.lineWidth = 4
arrowHead.stroke()

if let mascot = NSImage(contentsOf: mascotURL) {
    let mascotRect = NSRect(x: 288, y: 278, width: 104, height: 75)
    mascot.draw(in: mascotRect, from: .zero, operation: .sourceOver, fraction: 1)
}

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to render DMG background\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try png.write(to: outputURL)
