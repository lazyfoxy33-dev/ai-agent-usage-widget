import AppKit

/// Icon preparation for the black Touch Bar.
///
/// The assets are app-style tiles: some ship on an opaque light plate (Codex is a
/// white rounded square), which reads as an ugly white block on the bar. Detect a
/// light opaque corner and key that colour out, keeping the glyph itself.
///
/// Pixel work goes through Core Graphics rather than NSBitmapImageRep's colour
/// APIs, which fail with "unrecognized colorspace" on these assets.
enum ProviderIcon {
    private static var cache: [String: NSImage] = [:]

    static func condensed(_ image: NSImage, cacheKey: String? = nil) -> NSImage {
        if let cacheKey, let cached = cache[cacheKey] { return cached }
        let prepared = keyedOut(image) ?? image
        if let cacheKey { cache[cacheKey] = prepared }
        return prepared
    }

    /// Returns a transparent-background version, or nil when there is nothing to key.
    static func keyedOut(_ image: NSImage, side: Int = 64) -> NSImage? {
        guard side > 1,
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              var pixels = rgba(from: source, side: side),
              let plate = lightPlateColor(pixels: pixels, side: side) else {
            return nil
        }

        let threshold = 0.10
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0 else { continue }
            // Straight (un-premultiplied) colour for comparison.
            let red = Double(pixels[index]) / 255 / alpha
            let green = Double(pixels[index + 1]) / 255 / alpha
            let blue = Double(pixels[index + 2]) / 255 / alpha
            let distance = sqrt(
                pow(red - plate.0, 2) + pow(green - plate.1, 2) + pow(blue - plate.2, 2)
            )
            if distance < threshold {
                pixels[index] = 0
                pixels[index + 1] = 0
                pixels[index + 2] = 0
                pixels[index + 3] = 0
            } else if distance < threshold * 2 {
                // Feather the edge so the glyph does not look cut out.
                let factor = (distance - threshold) / threshold
                for channel in 0..<4 {
                    pixels[index + channel] = UInt8(
                        (Double(pixels[index + channel]) * factor).rounded()
                    )
                }
            }
        }

        guard let output = nsImage(pixels: pixels, side: side) else { return nil }
        return output
    }

    /// The plate colour when all four corners are opaque and light.
    static func lightPlateColor(pixels: [UInt8], side: Int) -> (Double, Double, Double)? {
        let last = side - 1
        let corners = [(0, 0), (last, 0), (0, last), (last, last)]
        var samples: [(Double, Double, Double, Double)] = []
        for (x, y) in corners {
            let index = (y * side + x) * 4
            guard index + 3 < pixels.count else { return nil }
            let alpha = Double(pixels[index + 3]) / 255
            samples.append((
                Double(pixels[index]) / 255,
                Double(pixels[index + 1]) / 255,
                Double(pixels[index + 2]) / 255,
                alpha
            ))
        }
        let count = Double(samples.count)
        let alpha = samples.map(\.3).reduce(0, +) / count
        guard alpha > 0.85 else { return nil }   // transparent background: nothing to key
        guard samples.allSatisfy({ $0.3 > 0.85 }) else { return nil }
        let red = samples.map(\.0).reduce(0, +) / count
        let green = samples.map(\.1).reduce(0, +) / count
        let blue = samples.map(\.2).reduce(0, +) / count
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        guard luminance > 0.72 else { return nil }   // a coloured plate is part of the brand
        return (red, green, blue)
    }

    // MARK: Core Graphics plumbing

    private static func rgba(from source: CGImage, side: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return ok ? pixels : nil
    }

    private static func nsImage(pixels: [UInt8], side: Int) -> NSImage? {
        var mutable = pixels
        guard let provider = CGDataProvider(data: Data(mutable) as CFData),
              let cgImage = CGImage(
                width: side,
                height: side,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }
        mutable.removeAll()
        let result = NSImage(size: NSSize(width: 18, height: 18))
        result.addRepresentation(NSBitmapImageRep(cgImage: cgImage))
        return result
    }
}
