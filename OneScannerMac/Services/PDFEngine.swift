import AppKit
import ImageIO
@preconcurrency import PDFKit
@preconcurrency import Quartz
import UniformTypeIdentifiers

/// Every PDFKit job runs here, off the main actor: opening files, page pictures, writing new files, compressing.
/// Opened documents stay cached by URL for the session; originals are only read, never written.
actor PDFEngine {
    static let shared = PDFEngine()

    enum OpenResult: Sendable {
        case opened(pageCount: Int)
        case needsPassword
        case unreadable
    }

    enum EngineError: LocalizedError {
        case missingPage
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .missingPage: String(localized: "A page of this file can't be read anymore. Open the file again.")
            case .writeFailed: String(localized: "The PDF couldn't be made. Try again.")
            }
        }
    }

    private var documents: [URL: PDFDocument] = [:]
    private var stampImages: [URL: CGImage] = [:]
    private var compactStamps: [CompactKey: CompactStamp] = [:]
    private var filters: [CompressionStep: QuartzFilter] = [:]

    // MARK: Opening

    /// Opens a PDF or an image (an image becomes a one-page PDF, its long side 842 pt like A4). A locked PDF needs
    /// `password`; a wrong one answers `.needsPassword` again.
    func open(_ url: URL, password: String? = nil) -> OpenResult {
        if let document = documents[url], !document.isLocked { return .opened(pageCount: document.pageCount) }
        _ = url.startAccessingSecurityScopedResource()
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        if type?.conforms(to: .pdf) == true {
            guard let document = documents[url] ?? PDFDocument(url: url) else { return .unreadable }
            if document.isLocked {
                guard let password, document.unlock(withPassword: password) else {
                    documents[url] = document
                    return .needsPassword
                }
            }
            documents[url] = document
            return document.pageCount > 0 ? .opened(pageCount: document.pageCount) : .unreadable
        }
        guard let image = NSImage(contentsOf: url), image.isValid,
              let page = Self.page(from: image) else { return .unreadable }
        let document = PDFDocument()
        document.insert(page, at: 0)
        documents[url] = document
        return .opened(pageCount: 1)
    }

    func forget(_ url: URL) {
        documents[url] = nil
    }

    private static func page(from image: NSImage) -> PDFPage? {
        // The image's real pixels, not its point size (a 300 dpi scan reports a small point size).
        let pixels = image.representations.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) }
            .max { $0.width * $0.height < $1.width * $1.height } ?? image.size
        let size = pixels.width > 0 && pixels.height > 0 ? pixels : image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = 842 / max(size.width, size.height)
        let box = CGRect(x: 0, y: 0, width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        return PDFPage(image: image, options: [.mediaBox: NSValue(rect: box), .compressionQuality: 0.9])
    }

    // MARK: Pages

    private func page(_ source: PageSource) throws -> PDFPage {
        guard let page = documents[source.url]?.page(at: source.index) else { throw EngineError.missingPage }
        return page
    }

    /// The page's size as shown with `turn` applied, in points.
    func displaySize(_ source: PageSource, turn: Int) -> CGSize {
        guard let page = try? page(source) else { return CGSize(width: 595, height: 842) }
        return Self.displaySize(page, rotation: page.rotation + turn)
    }

    private static func displaySize(_ page: PDFPage, rotation: Int) -> CGSize {
        let box = page.bounds(for: .cropBox).size
        return Normalized.angle(rotation) % 180 == 0 ? box : CGSize(width: box.height, height: box.width)
    }

    /// A picture of the page as shown (turn applied), its long side `longSide` pixels, white behind it.
    func image(_ source: PageSource, turn: Int, longSide: CGFloat) -> SendableImage? {
        guard let page = try? page(source) else { return nil }
        let original = page.rotation
        page.rotation = Normalized.angle(original + turn)
        defer { page.rotation = original }
        let size = Self.displaySize(page, rotation: page.rotation)
        let scale = longSide / max(size.width, size.height, 1)
        let width = max(1, Int((size.width * scale).rounded())), height = max(1, Int((size.height * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)
        return context.makeImage().map(SendableImage.init)
    }

    /// The page as a picture for reading codes: about 2,400 pixels on the long side.
    func codeImage(_ source: PageSource) -> SendableImage? {
        image(source, turn: 0, longSide: 2400)
    }

    // MARK: Writing

    /// The finished PDF as data: pages in order with their turns, stamps drawn into their pages, optional password
    /// and image compression. Pages without stamps are copied as they are (text, links and form fields kept).
    func build(_ plan: BuildPlan) throws -> Data {
        if let step = plan.quality, step.pagesAsPictures { return try buildAsPictures(plan, step: step) }
        var sources: [(page: PDFPage, rotation: Int)] = []
        for item in plan.pages {
            let source = try page(item.source)
            sources.append((source, Normalized.angle(source.rotation + item.turn)))
        }
        let filter = plan.quality.flatMap(filter(for:))
        let hasStamps = plan.pages.contains { !$0.stamps.isEmpty }
        // With stamps, the pictures in the pages shrink first and the stamps go on afterwards at the step's own
        // size: the filter would re-encode a stamp's JPEG losslessly and make it bigger. `filtered` keeps its pages
        // alive (a page holds its document weakly).
        var filtered: PDFDocument?
        if let filter, hasStamps {
            let plain = try assemble(sources.map { ($0.page, $0.rotation, []) }, files: [:], quality: nil)
            try Task.checkCancellation()
            guard let data = plain.dataRepresentation(options: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]),
                  let document = PDFDocument(data: data), document.pageCount == sources.count else {
                throw EngineError.writeFailed
            }
            filtered = document
            sources = (0..<document.pageCount).compactMap { index in
                document.page(at: index).map { ($0, $0.rotation) }
            }
        }
        let output = try assemble(zip(sources, plan.pages).map { ($0.page, $0.rotation, $1.stamps) },
                                  files: plan.stampFiles, quality: plan.quality)
        var options: [PDFDocumentWriteOption: Any] = [:]
        if let password = plan.password, !password.isEmpty {
            options[.userPasswordOption] = password
            options[.ownerPasswordOption] = password
        }
        if let filter, filtered == nil {
            options[PDFDocumentWriteOption(rawValue: "QuartzFilter")] = filter
        }
        try Task.checkCancellation()
        guard let data = output.dataRepresentation(options: options) else { throw EngineError.writeFailed }
        withExtendedLifetime(filtered) {}
        return data
    }

    /// The last resort of "Up to N MB": every page (stamps included) as one JPEG picture, `step.maxPixels` on its long
    /// side, on a page of the same size. The JPEG goes into the file as it is; the password, if any, is kept.
    private func buildAsPictures(_ plan: BuildPlan, step: CompressionStep) throws -> Data {
        var plain = plan
        plain.password = nil
        plain.quality = nil
        guard let document = PDFDocument(data: try build(plain)) else { throw EngineError.writeFailed }
        let output = NSMutableData()
        var info: [CFString: Any] = [kCGPDFContextCreator: "1Scanner"]
        if let password = plan.password, !password.isEmpty {
            info[kCGPDFContextUserPassword] = password
            info[kCGPDFContextOwnerPassword] = password
        }
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: output),
              let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary) else { throw EngineError.writeFailed }
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw EngineError.missingPage }
            let size = Self.displaySize(page, rotation: page.rotation)
            let scale = Double(step.maxPixels) / max(size.width, size.height, 1)
            let width = max(1, Int((size.width * scale).rounded())), height = max(1, Int((size.height * scale).rounded()))
            guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                throw EngineError.writeFailed
            }
            bitmap.setFillColor(.white)
            bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
            bitmap.interpolationQuality = .high
            bitmap.scaleBy(x: scale, y: scale)
            page.draw(with: .cropBox, to: bitmap)
            let jpeg = NSMutableData()
            guard let picture = bitmap.makeImage(),
                  let destination = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw EngineError.writeFailed
            }
            CGImageDestinationAddImage(destination, picture,
                                       [kCGImageDestinationLossyCompressionQuality: step.jpegQuality] as CFDictionary)
            guard CGImageDestinationFinalize(destination), let provider = CGDataProvider(data: jpeg),
                  let image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true,
                                      intent: .defaultIntent) else { throw EngineError.writeFailed }
            var media = CGRect(origin: .zero, size: size)
            context.beginPage(mediaBox: &media)
            context.draw(image, in: media)
            context.endPage()
        }
        context.closePDF()
        return output as Data
    }

    /// Pages in order: unstamped ones copied as they are (text, links and form fields kept), stamped ones redrawn
    /// with their stamps.
    private func assemble(_ pages: [(page: PDFPage, rotation: Int, stamps: [StampPlacement])], files: [UUID: URL],
                          quality: CompressionStep?) throws -> PDFDocument {
        let output = PDFDocument()
        for item in pages {
            try Task.checkCancellation()
            let page: PDFPage
            if item.stamps.isEmpty {
                guard let copy = item.page.copy() as? PDFPage else { throw EngineError.writeFailed }
                copy.rotation = item.rotation
                page = copy
            } else {
                page = try stamped(item.page, rotation: item.rotation, stamps: item.stamps, files: files, quality: quality)
            }
            output.insert(page, at: output.pageCount)
        }
        return output
    }

    /// Every page of the plan as a picture (stamps included): PNG, or JPEG at quality 0.85.
    func pictures(_ plan: BuildPlan, dpi: Double, jpeg: Bool) throws -> [Data] {
        var plain = plan
        plain.password = nil
        plain.quality = nil
        guard let document = PDFDocument(data: try build(plain)) else { throw EngineError.writeFailed }
        var result: [Data] = []
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw EngineError.missingPage }
            let size = Self.displaySize(page, rotation: page.rotation)
            let scale = dpi / 72
            let width = max(1, Int((size.width * scale).rounded())), height = max(1, Int((size.height * scale).rounded()))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw EngineError.writeFailed }
            context.setFillColor(.white)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .high
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .cropBox, to: context)
            guard let image = context.makeImage(),
                  let data = NSBitmapImageRep(cgImage: image).representation(
                      using: jpeg ? .jpeg : .png, properties: jpeg ? [.compressionFactor: 0.85] : [:]) else {
                throw EngineError.writeFailed
            }
            result.append(data)
        }
        return result
    }

    /// The page drawn into a new one-page PDF as shown, with its stamps on top. The page's own content stays text and
    /// vector drawing. Each stamp goes in at the size it's placed (`compactStamp`), not as its full library PNG.
    private func stamped(_ source: PDFPage, rotation: Int, stamps: [StampPlacement], files: [UUID: URL],
                         quality: CompressionStep?) throws -> PDFPage {
        let original = source.rotation
        source.rotation = rotation
        defer { source.rotation = original }
        let size = Self.displaySize(source, rotation: rotation)
        var box = CGRect(origin: .zero, size: size)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw EngineError.writeFailed }
        context.beginPDFPage(nil)
        source.draw(with: .cropBox, to: context)
        for stamp in stamps {
            guard let url = files[stamp.stampID], let full = stampImage(url) else { continue }
            let aspect = Double(full.width) / Double(max(full.height, 1))
            let width = stamp.width * size.width
            let height = width / max(aspect, 0.001)
            // 300 dpi as it is; with compression the step's resolution (Medium 200, Small 130, floor 100 dpi).
            let dpi = quality.map { min(max(Double($0.maxPixels) / 10, 100), 200) } ?? 300
            let longSide = Int((max(width, height) * dpi / 72).rounded(.up))
            let compact = compactStamp(url, full: full, longSide: longSide, jpegQuality: quality?.jpegQuality ?? 0.85)
            context.saveGState()
            context.translateBy(x: stamp.center.x * size.width, y: (1 - stamp.center.y) * size.height)
            context.rotate(by: -stamp.rotation * .pi / 180)
            context.interpolationQuality = .high
            let frame = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
            if let compact {
                // The transparency as a clip, so the JPEG goes into the file as it is.
                context.clip(to: frame, mask: compact.alpha)
                context.draw(compact.color, in: frame)
            } else {
                context.draw(full, in: frame)
            }
            context.restoreGState()
        }
        context.endPDFPage()
        context.closePDF()
        guard let page = PDFDocument(data: data as Data)?.page(at: 0) else { throw EngineError.writeFailed }
        return page
    }

    private struct CompactKey: Hashable {
        let url: URL
        let longSide: Int
        let jpegQuality: Double
    }

    /// A stamp ready for a PDF: its colour as JPEG and its transparency as a separate grey mask.
    private struct CompactStamp {
        let color: CGImage
        let alpha: CGImage
    }

    /// The stamp at `longSide` pixels as a JPEG plus a transparency mask. A PNG with alpha would go into the PDF
    /// losslessly at full size (a scanned seal: ~0.8 MB), and macOS's compression filter never touches images with
    /// transparency; this way a seal is ~0.1–0.2 MB and looks the same.
    private func compactStamp(_ url: URL, full: CGImage, longSide: Int, jpegQuality: Double) -> CompactStamp? {
        let scale = min(1, Double(longSide) / Double(max(full.width, full.height)))
        let width = max(1, Int((Double(full.width) * scale).rounded())), height = max(1, Int((Double(full.height) * scale).rounded()))
        let key = CompactKey(url: url, longSide: max(width, height), jpegQuality: jpegQuality)
        if let cached = compactStamps[key] { return cached }
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: sRGB,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(full, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // Colour without premultiplied alpha; fully transparent pixels take the ink's average colour, so the JPEG
        // has no hard edges to spend bytes on.
        var sum = [0.0, 0.0, 0.0], count = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 3] > 200 {
            for channel in 0..<3 { sum[channel] += Double(pixels[index + channel]) * 255 / Double(pixels[index + 3]) }
            count += 1
        }
        let ink = count > 0 ? sum.map { UInt8($0 / count) } : [0, 0, 0]
        var color = [UInt8](repeating: 0, count: width * height * 3)
        var alpha = [UInt8](repeating: 0, count: width * height)
        for pixel in 0..<(width * height) {
            let a = pixels[pixel * 4 + 3]
            alpha[pixel] = a
            for channel in 0..<3 {
                color[pixel * 3 + channel] = a < 8 ? ink[channel]
                    : UInt8(min(255, Int(pixels[pixel * 4 + channel]) * 255 / Int(a)))
            }
        }
        guard let colorProvider = CGDataProvider(data: Data(color) as CFData),
              let rgb = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: width * 3,
                                space: sRGB, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                provider: colorProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        let jpeg = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, rgb, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let jpegProvider = CGDataProvider(data: jpeg),
              let base = CGImage(jpegDataProviderSource: jpegProvider, decode: nil, shouldInterpolate: true,
                                 intent: .defaultIntent),
              let maskProvider = CGDataProvider(data: Data(alpha) as CFData),
              let mask = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                                 space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                 provider: maskProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        let result = CompactStamp(color: base, alpha: mask)
        compactStamps[key] = result
        return result
    }

    private func stampImage(_ url: URL) -> CGImage? {
        if let cached = stampImages[url] { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        stampImages[url] = image
        return image
    }

    /// A Quartz filter that scales page pictures down and re-encodes them as JPEG (the same mechanism as macOS's own
    /// "Reduce File Size", with our settings).
    private func filter(for step: CompressionStep) -> QuartzFilter? {
        if let cached = filters[step] { return cached }
        let settings: [String: Any] = [
            "Domains": ["Applications": true, "Printing": true],
            "FilterData": ["ColorSettings": ["ImageSettings": [
                "Compression Quality": step.jpegQuality,
                "ImageCompression": "ImageJPEGCompress",
                "ImageScaleSettings": [
                    "ImageScaleFactor": 0.0,
                    "ImageScaleInterpolate": true,
                    "ImageSizeMax": step.maxPixels,
                    "ImageSizeMin": 0,
                ],
            ]]],
            "FilterType": 1,
            "Name": "1Scanner \(step.maxPixels) \(step.jpegQuality)",
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compress-\(step.maxPixels)-\(Int(step.jpegQuality * 100)).qfilter")
        guard let data = try? PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0),
              (try? data.write(to: url)) != nil,
              let filter = QuartzFilter(url: url) else { return nil }
        filters[step] = filter
        return filter
    }
}

/// A finished picture handed from the engine to the UI.
struct SendableImage: @unchecked Sendable {
    let cgImage: CGImage
}
