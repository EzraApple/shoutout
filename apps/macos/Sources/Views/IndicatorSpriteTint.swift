import AppKit

enum IndicatorSpriteTint {
    static func tintedImage(_ image: NSImage, color: NSColor) -> NSImage? {
        guard let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let target = color.usingColorSpace(.sRGB),
              let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: bitmap.pixelsWide,
                    pixelsHigh: bitmap.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bitmapFormat: .alphaNonpremultiplied, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }

        // Ocean's body mid-tone is #3468BC. Keep dark outlines and lighter highlights.
        let bodyBrightness = 188.0 / 255.0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let source = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      source.alphaComponent > 0 else { continue }
                let brightness = max(source.redComponent, source.greenComponent, source.blueComponent)
                func shade(_ channel: CGFloat) -> CGFloat {
                    if brightness <= bodyBrightness { return channel * brightness / bodyBrightness }
                    return channel + (1 - channel) * (brightness - bodyBrightness) / (1 - bodyBrightness)
                }
                var pixel = [shade(target.redComponent), shade(target.greenComponent),
                             shade(target.blueComponent), source.alphaComponent]
                    .map { UInt(min(255, max(0, ($0 * 255).rounded()))) }
                output.setPixel(&pixel, atX: x, y: y)
            }
        }
        guard let result = output.retagging(with: .sRGB)?.cgImage else { return nil }
        return NSImage(cgImage: result, size: image.size)
    }
}
