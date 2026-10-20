import Foundation

/// Compress (docs/PRODUCT.md): Original, Medium, Small, or "Up to N MB" for portals, forms and email, the same
/// choices and ladder as 1Scanner for iPhone. Only the pictures inside the PDF are scaled down and re-encoded; text
/// and drawings stay sharp and selectable. Sizes are decimal (1 MB = 1,000,000 bytes), like every size the app shows.
enum Compression {
    enum Choice: Hashable, Sendable {
        case original, medium, small, upTo
    }

    static let medium = CompressionStep(maxPixels: 2000, jpegQuality: 0.7)
    static let small = CompressionStep(maxPixels: 1300, jpegQuality: 0.55)

    /// From the file as it is down to the floor that keeps scans readable (1,000 px, JPEG 0.35); each step makes a
    /// smaller file than the one before. `nil` is no compression. Text stays text on every step.
    static let ladder: [CompressionStep?] = [
        nil,
        medium,
        CompressionStep(maxPixels: 1800, jpegQuality: 0.62),
        CompressionStep(maxPixels: 1600, jpegQuality: 0.55),
        small,
        CompressionStep(maxPixels: 1300, jpegQuality: 0.45),
        CompressionStep(maxPixels: 1150, jpegQuality: 0.4),
        CompressionStep(maxPixels: 1000, jpegQuality: 0.35),
    ]

    /// The last resort of "Up to N MB" when the ladder above can't reach the limit: whole pages as
    /// JPEG pictures. The maintainer prefers a file that fits over a sharp one, so it goes below iPhone's floor down to
    /// 700 px on the long side at JPEG 0.2 (small print gets hard to read there).
    static let pictureLadder: [CompressionStep?] = [
        CompressionStep(maxPixels: 2000, jpegQuality: 0.6, pagesAsPictures: true),
        CompressionStep(maxPixels: 1600, jpegQuality: 0.5, pagesAsPictures: true),
        CompressionStep(maxPixels: 1300, jpegQuality: 0.45, pagesAsPictures: true),
        CompressionStep(maxPixels: 1150, jpegQuality: 0.4, pagesAsPictures: true),
        CompressionStep(maxPixels: 1000, jpegQuality: 0.35, pagesAsPictures: true),
        CompressionStep(maxPixels: 900, jpegQuality: 0.3, pagesAsPictures: true),
        CompressionStep(maxPixels: 800, jpegQuality: 0.25, pagesAsPictures: true),
        CompressionStep(maxPixels: 700, jpegQuality: 0.2, pagesAsPictures: true),
    ]

    /// The slider's stops: 0.2 · 0.3 · 0.5 · 0.75 · 1 · 1.5 · 2 · 3 · 4 · 5 · 7.5 · 10 · 15 · 20 MB.
    static let limits: [Int] = [
        200_000, 300_000, 500_000, 750_000, 1_000_000, 1_500_000, 2_000_000, 3_000_000, 4_000_000, 5_000_000,
        7_500_000, 10_000_000, 15_000_000, 20_000_000,
    ]
    /// 1 MB the first time, then the last value.
    static let defaultLimit = 1_000_000
    static let limitKey = "compress.targetBytes"

    struct Fit: Sendable {
        let data: Data
        /// False: even the floor is larger than the limit; `data` is the smallest file the app can make.
        let reached: Bool
        /// The pages became pictures: text in this copy can't be selected or searched.
        let pagesAsPictures: Bool
    }

    /// The best step whose file is no larger than `limit`: the file as it is when it fits, else halving between the
    /// steps that keep text (at most about five builds); only when even their floor is too big, the same search over
    /// pages as pictures. When nothing fits, the smallest file made.
    @MainActor static func fit(limit: Int, build: (CompressionStep?) async throws -> Data) async throws -> Fit {
        let text = try await search(ladder, limit: limit, build: build)
        if text.reached { return Fit(data: text.data, reached: true, pagesAsPictures: false) }
        let pictures = try await search(pictureLadder, limit: limit, build: build)
        if pictures.reached || pictures.data.count < text.data.count {
            return Fit(data: pictures.data, reached: pictures.reached, pagesAsPictures: true)
        }
        return Fit(data: text.data, reached: false, pagesAsPictures: false)
    }

    @MainActor private static func search(_ steps: [CompressionStep?], limit: Int,
                                          build: (CompressionStep?) async throws -> Data) async throws -> (data: Data, reached: Bool) {
        var built: [Int: Data] = [:]
        func size(at index: Int) async throws -> Int {
            if let known = built[index] { return known.count }
            try Task.checkCancellation()
            let data = try await build(steps[index])
            built[index] = data
            return data.count
        }
        if try await size(at: 0) <= limit { return (built[0]!, true) }
        let floor = steps.count - 1
        if try await size(at: floor) > limit { return (built[floor]!, false) }
        var low = 1, high = floor
        while low < high {
            let middle = (low + high) / 2
            if try await size(at: middle) <= limit { high = middle } else { low = middle + 1 }
        }
        return (built[high]!, true)
    }

    /// "1 MB", "0.75 MB" in the app's language ("1 Mo", "0,75 МБ").
    static func limitTitle(_ bytes: Int) -> String {
        Measurement(value: Double(bytes) / 1_000_000, unit: UnitInformationStorage.megabytes)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(0...2))))
    }
}
