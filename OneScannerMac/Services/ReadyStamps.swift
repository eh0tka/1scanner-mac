import CoreText
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

/// Ready stamps (same as 1Scanner for iPhone): APPROVED, PAID, COPY, CONFIDENTIAL, DRAFT, RECEIVED and today's date,
/// drawn by the app like a rubber stamp in the app language, in red, blue or black, optionally with today's date. A
/// chosen ready stamp is saved in the library under a fixed ID, so choosing it again reuses it; a placed stamp is an
/// image and never changes afterwards. "Your own word" makes the same stamp from the person's word.
enum ReadyStamp: String, CaseIterable, Identifiable, Sendable {
    case approved, paid, copy, confidential, draft, received, date

    var id: String { rawValue }

    /// The stamp's word in the app language ("PAGADO", "BEZAHLT"); nil for the date alone.
    var word: String? {
        switch self {
        case .approved: String(localized: "APPROVED")
        case .paid: String(localized: "PAID")
        case .copy: String(localized: "COPY")
        case .confidential: String(localized: "CONFIDENTIAL")
        case .draft: String(localized: "DRAFT")
        case .received: String(localized: "RECEIVED")
        case .date: nil
        }
    }
}

enum StampInk: String, CaseIterable, Identifiable, Sendable {
    case red, blue, black

    var id: String { rawValue }

    var cgColor: CGColor {
        switch self {
        case .red: CGColor(red: 0.80, green: 0.07, blue: 0.09, alpha: 0.92)
        case .blue: CGColor(red: 0.10, green: 0.23, blue: 0.70, alpha: 0.92)
        case .black: CGColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 0.92)
        }
    }

    var color: Color { Color(cgColor: cgColor) }

    var title: LocalizedStringKey {
        switch self {
        case .red: "Red"
        case .blue: "Blue"
        case .black: "Black"
        }
    }
}

enum ReadyStampRenderer {
    /// A transparent PNG: the word in capitals inside a rounded double frame, and the date below it when given.
    static func render(word: String?, date: String?, ink: StampInk) -> StampMaker.Stamp? {
        let lines = [word, date].compactMap { $0 }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        let wordSize: CGFloat = 150
        let dateSize: CGFloat = word == nil ? 120 : 78
        func line(_ text: String, size: CGFloat) -> CTLine {
            let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
                ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink.cgColor,
                NSAttributedString.Key(kCTKernAttributeName as String): size * 0.06
            ]
            return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        }
        let ctLines = lines.enumerated().map { index, text in
            line(text, size: word != nil && index == 0 ? wordSize : dateSize)
        }
        let metrics = ctLines.map { ctLine -> (width: CGFloat, ascent: CGFloat, descent: CGFloat) in
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, nil))
            return (width, ascent, descent)
        }
        let spacing: CGFloat = 26
        let padding: CGFloat = 70
        let textWidth = metrics.map(\.width).max() ?? 0
        let textHeight = metrics.reduce(0) { $0 + $1.ascent + $1.descent } + spacing * CGFloat(max(ctLines.count - 1, 0))
        let width = Int((textWidth + padding * 2).rounded(.up))
        let height = Int((textHeight + padding * 1.6).rounded(.up))
        guard width > 0, height > 0, let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setStrokeColor(ink.cgColor)
        context.setLineWidth(14)
        context.addPath(CGPath(roundedRect: bounds.insetBy(dx: 10, dy: 10), cornerWidth: 34, cornerHeight: 34, transform: nil))
        context.strokePath()
        context.setLineWidth(5)
        context.addPath(CGPath(roundedRect: bounds.insetBy(dx: 32, dy: 32), cornerWidth: 20, cornerHeight: 20, transform: nil))
        context.strokePath()
        context.textMatrix = .identity
        var y = CGFloat(height) - padding * 0.8
        for (ctLine, metric) in zip(ctLines, metrics) {
            y -= metric.ascent
            context.textPosition = CGPoint(x: (CGFloat(width) - metric.width) / 2, y: y)
            CTLineDraw(ctLine, context)
            y -= metric.descent + spacing
        }
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return StampMaker.Stamp(png: data as Data, pixelWidth: width, pixelHeight: height)
    }

    /// The same word, color and date always give the same ID, so each ready stamp is written once.
    static func stampID(word: String?, date: String?, ink: StampInk) -> UUID {
        let digest = SHA256.hash(data: Data("ready|\(word ?? "")|\(date ?? "")|\(ink.rawValue)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Today's date as a stamp shows it, in the app language.
    static func today() -> String {
        Date().formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: .current))
    }
}
