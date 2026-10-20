import Foundation
import Vision

/// The kinds of codes the camera and photos read (docs/PRODUCT.md §4.2): 2D codes, product codes and 1D codes.
enum CodeSymbology: String, Codable, Hashable, Sendable {
    case qr, microQR, aztec, dataMatrix, pdf417
    case ean13, ean8, upce
    case code39, code93, code128, itf14, i2of5, codabar, gs1DataBar, msiPlessey
    case other

    init(_ symbology: VNBarcodeSymbology) {
        switch symbology {
        case .qr: self = .qr
        case .microQR: self = .microQR
        case .aztec: self = .aztec
        case .dataMatrix: self = .dataMatrix
        case .pdf417, .microPDF417: self = .pdf417
        case .ean13: self = .ean13
        case .ean8: self = .ean8
        case .upce: self = .upce
        case .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum: self = .code39
        case .code93, .code93i: self = .code93
        case .code128: self = .code128
        case .itf14: self = .itf14
        case .i2of5, .i2of5Checksum: self = .i2of5
        case .codabar: self = .codabar
        case .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited: self = .gs1DataBar
        case .msiPlessey: self = .msiPlessey
        default: self = .other
        }
    }

    /// Everything Vision reads that the plan lists; checked against what the device supports.
    static let visionSymbologies: [VNBarcodeSymbology] = [
        .qr, .microQR, .aztec, .dataMatrix, .pdf417, .microPDF417,
        .ean13, .ean8, .upce,
        .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum, .code93, .code93i, .code128,
        .itf14, .i2of5, .i2of5Checksum, .codabar, .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited
    ]

    /// Codes read with a laser-style scanner: product numbers and other 1D codes.
    var isLinear: Bool {
        switch self {
        case .qr, .microQR, .aztec, .dataMatrix, .pdf417, .other: false
        default: true
        }
    }

    /// The name printed on the code's card ("QR code", "EAN-13").
    var displayName: String {
        switch self {
        case .qr: "QR"
        case .microQR: "Micro QR"
        case .aztec: "Aztec"
        case .dataMatrix: "Data Matrix"
        case .pdf417: "PDF417"
        case .ean13: "EAN-13"
        case .ean8: "EAN-8"
        case .upce: "UPC-E"
        case .code39: "Code 39"
        case .code93: "Code 93"
        case .code128: "Code 128"
        case .itf14: "ITF-14"
        case .i2of5: "Interleaved 2 of 5"
        case .codabar: "Codabar"
        case .gs1DataBar: "GS1 DataBar"
        case .msiPlessey: "MSI Plessey"
        case .other: String(localized: "Barcode", comment: "Card title of a code whose kind is unknown")
        }
    }
}
