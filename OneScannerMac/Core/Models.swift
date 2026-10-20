import CoreGraphics
import Foundation

/// A page of an opened file: page `index` of the PDF at `url`, or index 0 of an opened image (`PDFEngine` turns an
/// image into a one-page PDF when it opens it).
struct PageSource: Hashable, Sendable {
    let url: URL
    let index: Int
}

/// A signature or stamp placed on a page, measured on the page as it is shown (its turn applied): `center` is
/// normalized with the origin at the top left, `width` is a fraction of the page width, `rotation` is in degrees
/// clockwise. It stays a separate layer until a file is saved; saving draws it into the page.
struct StampPlacement: Identifiable, Hashable, Sendable {
    let id: UUID
    let stampID: UUID
    var center: CGPoint
    var width: Double
    var rotation: Double

    init(id: UUID = UUID(), stampID: UUID, center: CGPoint, width: Double, rotation: Double = 0) {
        self.id = id
        self.stampID = stampID
        self.center = center
        self.width = width
        self.rotation = rotation
    }

    /// The same placement after the page turned a quarter clockwise; `oldSize` is the page as shown before the turn.
    func turnedClockwise(oldSize: CGSize) -> StampPlacement {
        var result = self
        result.center = CGPoint(x: 1 - center.y, y: center.x)
        // The new page is as wide as the old one was high.
        result.width = width * oldSize.width / max(oldSize.height, 1)
        result.rotation = (rotation + 90).truncatingRemainder(dividingBy: 360)
        return result
    }
}

/// One page in an open file, in the file's current order.
struct PageItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let source: PageSource
    /// Quarter turns added in 1Scanner, in degrees clockwise (0, 90, 180, 270), on top of the page's own rotation.
    var turn: Int
    var stamps: [StampPlacement]

    init(source: PageSource, turn: Int = 0, stamps: [StampPlacement] = []) {
        id = UUID()
        self.source = source
        self.turn = turn
        self.stamps = stamps
    }

    /// A copy for another file (merge, extract), with its own identity.
    func duplicated() -> PageItem {
        PageItem(source: source, turn: turn, stamps: stamps.map {
            StampPlacement(stampID: $0.stampID, center: $0.center, width: $0.width, rotation: $0.rotation)
        })
    }
}

/// A saved signature or stamp (its PNG lives next to the library's index, only on this Mac).
struct StampRecord: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    let pixelWidth: Int
    let pixelHeight: Int

    var aspect: Double { Double(pixelWidth) / Double(max(pixelHeight, 1)) }
}

/// What a file is written with: its pages (with turns and stamps), the stamp images and an optional password.
struct BuildPlan: Sendable {
    var pages: [PageItem]
    var stampFiles: [UUID: URL]
    var password: String?
    var quality: CompressionStep?
}

/// One step of image compression: page pictures no larger than `maxPixels` on their long side, re-encoded as JPEG
/// at `jpegQuality`. Text and drawings stay as they are — unless `pagesAsPictures`, the last resort of "Up to N MB"
/// (as on iPhone): then each whole page becomes one JPEG picture of `maxPixels` on its long side,
/// and text in that copy can't be selected or searched.
struct CompressionStep: Hashable, Sendable {
    let maxPixels: Int
    let jpegQuality: Double
    var pagesAsPictures = false
}

enum Normalized {
    /// 0, 90, 180 or 270.
    static func angle(_ degrees: Int) -> Int {
        ((degrees % 360) + 360) % 360
    }
}
