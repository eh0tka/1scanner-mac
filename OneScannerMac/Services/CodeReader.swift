import CoreGraphics
import Foundation
import Vision

/// A code found in a file or a pasted picture.
struct FoundCode: Identifiable, Hashable, Sendable {
    let id = UUID()
    let payload: String
    let symbology: CodeSymbology
    /// Where it was found: a file name or "Pasted image".
    let origin: String
    /// The page of a PDF (1-based); nil for a picture.
    let page: Int?

    var content: CodeContent { CodeContent.parse(payload, symbology: symbology) }
}

/// Reads QR codes and barcodes with Apple's on-device Vision, from pictures and from every page of a PDF. Nothing
/// leaves the Mac; nothing opens by itself.
enum CodeReader {
    private static func request() -> VNDetectBarcodesRequest {
        let request = VNDetectBarcodesRequest()
        let supported = Set((try? request.supportedSymbologies()) ?? [])
        request.symbologies = CodeSymbology.visionSymbologies.filter { supported.contains($0) }
        return request
    }

    /// Codes in one picture, one per payload; call off the main actor.
    static func codes(in image: CGImage) -> [(payload: String, symbology: CodeSymbology)] {
        let request = request()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        var seen = Set<String>()
        var result: [(String, CodeSymbology)] = []
        // Top to bottom, then left to right, the way the page reads.
        let observations = (request.results ?? []).sorted {
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.02
                ? $0.boundingBox.midY > $1.boundingBox.midY
                : $0.boundingBox.midX < $1.boundingBox.midX
        }
        for observation in observations {
            guard let payload = observation.payloadStringValue, !payload.isEmpty, seen.insert(payload).inserted else { continue }
            result.append((payload, CodeSymbology(observation.symbology)))
        }
        return result
    }
}

extension PDFEngine {
    /// Every code on every page of an opened file (`open` first), page by page; stops when the task is cancelled.
    func codes(in url: URL, pageCount: Int, origin: String) throws -> [FoundCode] {
        var found: [FoundCode] = []
        for index in 0..<pageCount {
            try Task.checkCancellation()
            guard let image = codeImage(PageSource(url: url, index: index)) else { continue }
            for code in CodeReader.codes(in: image.cgImage) {
                found.append(FoundCode(payload: code.payload, symbology: code.symbology, origin: origin,
                                       page: pageCount > 1 || url.pathExtension.lowercased() == "pdf" ? index + 1 : nil))
            }
        }
        return found
    }
}
