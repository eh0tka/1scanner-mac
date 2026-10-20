import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns a photo or scan of a signature or stamp into a clean stamp (docs/PRODUCT.md §4.6.1): the paper becomes
/// transparent, the ink keeps its own color (a blue seal stays blue), and the image is cropped to the ink. An image
/// that already has transparency (a PNG, a drawing) is only cropped. Runs off the main actor, one image at a time.
actor StampMaker {
    static let shared = StampMaker()

    enum StampError: LocalizedError {
        case unreadable
        case noInk

        var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "This image can't be read.")
            case .noInk: String(localized: "No signature or stamp found. Try a photo of it on white paper.")
            }
        }
    }

    struct Stamp: Sendable {
        let png: Data
        let pixelWidth: Int
        let pixelHeight: Int
    }

    /// Longest side the ink is lifted at, and the longest side a saved stamp keeps.
    static let workingLongSide: CGFloat = 2000
    static let stampLongSide = 1200

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    func makeStamp(from data: Data) throws -> Stamp {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw StampError.unreadable }
        return try makeStamp(from: source)
    }

    func makeStamp(fromFile url: URL) throws -> Stamp {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw StampError.unreadable }
        return try makeStamp(from: source)
    }

    // MARK: Steps

    private func makeStamp(from source: CGImageSource) throws -> Stamp {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.workingLongSide
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              var pixels = bitmap(of: image) else { throw StampError.unreadable }
        let width = image.width, height = image.height
        try Task.checkCancellation()
        if !hasTransparency(pixels) {
            guard let background = paper(behind: image), let paper = bitmap(of: background) else {
                throw StampError.unreadable
            }
            try Task.checkCancellation()
            Self.liftInk(&pixels, paper: paper)
        }
        return try finish(pixels, width: width, height: height)
    }

    /// The paper alone: ink strokes are thin, so the lightest color around each point, softened, is the paper there,
    /// with its shadows and tint.
    private func paper(behind image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let radius = max(3, Double(max(image.width, image.height)) / 120)
        let maximum = CIFilter.morphologyMaximum()
        maximum.inputImage = input
        maximum.radius = Float(radius)
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = maximum.outputImage?.clampedToExtent()
        blur.radius = Float(radius * 2)
        guard let output = blur.outputImage?.cropped(to: input.extent) else { return nil }
        return context.createCGImage(output, from: input.extent)
    }

    /// Each pixel divided by the paper under it: paper becomes white. Alpha is how dark the darkest channel is, so a
    /// colored ink counts as fully as black; the ink's color is recovered from partly covered edge pixels.
    private static func liftInk(_ pixels: inout [UInt8], paper: [UInt8]) {
        let lower: Float = 0.12, upper: Float = 0.42
        pixels.withUnsafeMutableBufferPointer { out in
            paper.withUnsafeBufferPointer { bg in
                var index = 0
                while index < out.count {
                    let r = min(1, Float(out[index]) / max(Float(bg[index]), 40))
                    let g = min(1, Float(out[index + 1]) / max(Float(bg[index + 1]), 40))
                    let b = min(1, Float(out[index + 2]) / max(Float(bg[index + 2]), 40))
                    let darkness = 1 - min(r, g, b)
                    let t = min(max((darkness - lower) / (upper - lower), 0), 1)
                    let alpha = t * t * (3 - 2 * t)
                    if alpha < 0.02 {
                        out[index] = 0; out[index + 1] = 0; out[index + 2] = 0; out[index + 3] = 0
                    } else {
                        // observed = alpha × ink + (1 − alpha) × white
                        let inkR = max(0, 1 - (1 - r) / alpha)
                        let inkG = max(0, 1 - (1 - g) / alpha)
                        let inkB = max(0, 1 - (1 - b) / alpha)
                        out[index] = UInt8(inkR * alpha * 255)
                        out[index + 1] = UInt8(inkG * alpha * 255)
                        out[index + 2] = UInt8(inkB * alpha * 255)
                        out[index + 3] = UInt8(alpha * 255)
                    }
                    index += 4
                }
            }
        }
    }

    /// True when the image carries real transparency (a PNG stamp, a drawing): then only cropping is needed.
    private func hasTransparency(_ pixels: [UInt8]) -> Bool {
        var transparent = 0
        var index = 3
        while index < pixels.count {
            if pixels[index] < 200 { transparent += 1 }
            index += 4
        }
        return Double(transparent) / Double(max(pixels.count / 4, 1)) > 0.02
    }

    /// Crops to the ink (rows and columns with at least three ink pixels, so single specks near the edge don't count),
    /// adds a small margin, scales down to the saved size and encodes a PNG.
    private func finish(_ pixels: [UInt8], width: Int, height: Int) throws -> Stamp {
        var rowCounts = [Int](repeating: 0, count: height)
        var columnCounts = [Int](repeating: 0, count: width)
        for y in 0..<height {
            let row = y * width * 4
            for x in 0..<width where pixels[row + x * 4 + 3] > 25 {
                rowCounts[y] += 1
                columnCounts[x] += 1
            }
        }
        guard let top = rowCounts.firstIndex(where: { $0 >= 3 }),
              let bottom = rowCounts.lastIndex(where: { $0 >= 3 }),
              let left = columnCounts.firstIndex(where: { $0 >= 3 }),
              let right = columnCounts.lastIndex(where: { $0 >= 3 }),
              right - left >= 8, bottom - top >= 8 else { throw StampError.noInk }
        let margin = max(4, max(right - left, bottom - top) / 40)
        let crop = CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
            .insetBy(dx: -CGFloat(margin), dy: -CGFloat(margin))
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard let full = image(from: pixels, width: width, height: height),
              let cropped = full.cropping(to: crop) else { throw StampError.unreadable }
        let scale = min(1, CGFloat(Self.stampLongSide) / CGFloat(max(cropped.width, cropped.height)))
        let outputWidth = max(1, Int((CGFloat(cropped.width) * scale).rounded()))
        let outputHeight = max(1, Int((CGFloat(cropped.height) * scale).rounded()))
        guard let canvas = CGContext(
            data: nil, width: outputWidth, height: outputHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw StampError.unreadable }
        canvas.interpolationQuality = .high
        canvas.draw(cropped, in: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))
        guard let result = canvas.makeImage() else { throw StampError.unreadable }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw StampError.unreadable
        }
        CGImageDestinationAddImage(destination, result, nil)
        guard CGImageDestinationFinalize(destination) else { throw StampError.unreadable }
        return Stamp(png: data as Data, pixelWidth: outputWidth, pixelHeight: outputHeight)
    }

    // MARK: Bitmaps

    /// Premultiplied RGBA, rows from the top.
    private func bitmap(of image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let canvas = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            canvas.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? pixels : nil
    }

    private func image(from pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
