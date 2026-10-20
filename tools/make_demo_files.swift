// Made-up documents for website screenshots (never the maintainer's files): a service agreement with a photo, a photo of
// a company seal and of a signature on paper, an invoice with QR codes and a Wi-Fi QR picture.
// Run from the app folder: swift tools/make_demo_files.swift <output folder> [language]
// The texts come from demo_texts.json next to this script (en when the language is missing). Then copy the files
// into the QA folder's in/ and launch the Debug build with -demoShots YES (see AGENTS.md).
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let language = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "en"

struct DemoTexts: Decodable {
    let file, page, title, between, project, annex, forStudio, forClient, signedOn, invoice, scanToPay, orderNote,
        wifiName: String
    let clauses: [String]
}
let texts: DemoTexts = {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("demo_texts.json")
    let all = try! JSONDecoder().decode([String: DemoTexts].self, from: Data(contentsOf: url))
    return all[language] ?? all["en"]!
}()
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
var random = SystemRandomNumberGenerator()

/// One line of text, made smaller when it would run past `maxWidth` (longer languages).
func text(_ s: String, _ ctx: CGContext, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular,
          color: NSColor = NSColor(white: 0.12, alpha: 1), maxWidth: CGFloat = 495) {
    func line(_ size: CGFloat) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]))
    }
    let width = CTLineGetTypographicBounds(line(size), nil, nil, nil)
    let line = line(width > maxWidth ? size * maxWidth / width : size)
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
}

/// A soft landscape "photo": sky, hills and grain, so it weighs like a real photo.
func photo(_ w: Int, _ h: Int) -> CGImage {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let sky = CGGradient(colorsSpace: sRGB, colors: [CGColor(red: 0.98, green: 0.78, blue: 0.55, alpha: 1),
                                                     CGColor(red: 0.45, green: 0.62, blue: 0.86, alpha: 1)] as CFArray,
                         locations: [0, 1])!
    c.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: h), options: [])
    for (index, shade) in [0.42, 0.32, 0.22].enumerated() {
        c.setFillColor(CGColor(red: shade * 0.6, green: shade + 0.1, blue: shade * 0.7, alpha: 1))
        c.move(to: CGPoint(x: 0, y: 0))
        let base = Double(h) * (0.45 - Double(index) * 0.12)
        for x in stride(from: 0, through: w, by: 8) {
            c.addLine(to: CGPoint(x: Double(x), y: base + sin(Double(x) / Double(w) * (3 + Double(index)) * .pi) * Double(h) * 0.08))
        }
        c.addLine(to: CGPoint(x: w, y: 0))
        c.fillPath()
    }
    for _ in 0..<Int(Double(w * h) / 30) {
        c.setFillColor(CGColor(gray: .random(in: 0...1, using: &random), alpha: 0.05))
        c.fill(CGRect(x: .random(in: 0...Double(w), using: &random), y: .random(in: 0...Double(h), using: &random), width: 2, height: 2))
    }
    return c.makeImage()!
}

func qr(_ s: String) -> CGImage {
    let f = CIFilter.qrCodeGenerator()
    f.message = Data(s.utf8)
    f.correctionLevel = "M"
    let img = f.outputImage!.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
    return CIContext().createCGImage(img, from: img.extent)!
}

func paper(_ c: CGContext, _ w: Int, _ h: Int) {
    let g = CGGradient(colorsSpace: sRGB, colors: [CGColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1),
                                                   CGColor(red: 0.80, green: 0.79, blue: 0.76, alpha: 1)] as CFArray,
                       locations: [0, 1])!
    c.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
}

func writeJPEG(_ image: CGImage, _ name: String) {
    try! NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.88])!
        .write(to: URL(fileURLWithPath: "\(out)/\(name)"))
}

let clauses = texts.clauses

// "Service Agreement.pdf" (its name in the chosen language): three A4 pages.
do {
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let ctx = CGContext(URL(fileURLWithPath: "\(out)/\(texts.file).pdf") as CFURL, mediaBox: &box, nil)!
    let accent = NSColor(red: 0.12, green: 0.33, blue: 0.42, alpha: 1)
    for page in 1...3 {
        ctx.beginPDFPage(nil)
        ctx.setFillColor(accent.cgColor)
        ctx.fill(CGRect(x: 0, y: 812, width: 595, height: 30))
        text("LUMEN & PINE STUDIO", ctx, x: 50, y: 822, size: 11, weight: .bold, color: .white)
        text(String(format: texts.page, page), ctx, x: 460, y: 822, size: 10, color: .white, maxWidth: 90)
        if page == 1 {
            text(texts.title, ctx, x: 50, y: 750, size: 30, weight: .bold)
            text(texts.between, ctx, x: 50, y: 724, size: 13, color: .darkGray)
            ctx.draw(photo(2400, 1300), in: CGRect(x: 50, y: 400, width: 495, height: 268))
            text(texts.project, ctx, x: 50, y: 372, size: 12, weight: .semibold)
        }
        var y: CGFloat = page == 1 ? 330 : 760
        for (index, clause) in clauses.enumerated() where page == 1 ? index < 3 : true {
            text("\(index + 1).", ctx, x: 50, y: y, size: 12, weight: .semibold)
            text(clause, ctx, x: 72, y: y, size: 12, maxWidth: 473)
            y -= 30
            if page == 2 { text("    " + texts.annex, ctx, x: 72, y: y, size: 10.5, color: .gray, maxWidth: 473); y -= 26 }
        }
        if page == 3 {
            ctx.setStrokeColor(NSColor.gray.cgColor)
            ctx.setLineWidth(0.8)
            for (x, who) in [(50.0, texts.forStudio), (320.0, texts.forClient)] {
                ctx.move(to: CGPoint(x: x, y: 250)); ctx.addLine(to: CGPoint(x: x + 220, y: 250)); ctx.strokePath()
                text(who, ctx, x: x, y: 234, size: 11, color: .darkGray, maxWidth: 220)
            }
            text(texts.signedOn, ctx, x: 50, y: 190, size: 11, color: .darkGray)
        }
        ctx.endPDFPage()
    }
    ctx.closePDF()
}

// A photo of a round red company seal on paper.
do {
    let w = 1400, h = 1400
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    paper(c, w, h)
    let ink = CGColor(red: 0.72, green: 0.10, blue: 0.14, alpha: 0.9)
    let center = CGPoint(x: 700, y: 700)
    c.setStrokeColor(ink)
    c.setLineWidth(22); c.strokeEllipse(in: CGRect(x: 200, y: 200, width: 1000, height: 1000))
    c.setLineWidth(7); c.strokeEllipse(in: CGRect(x: 300, y: 300, width: 800, height: 800))
    // Text around the ring.
    let words = "LUMEN & PINE STUDIO LTD · APPROVED · "
    let font = NSFont.systemFont(ofSize: 74, weight: .heavy)
    let count = words.count
    for (index, char) in words.enumerated() {
        let angle = .pi / 2 - Double(index) / Double(count) * 2 * .pi
        c.saveGState()
        c.translateBy(x: center.x + cos(angle) * 395, y: center.y + sin(angle) * 395)
        c.rotate(by: angle - .pi / 2)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(char), attributes: [
            .font: font, .foregroundColor: NSColor(cgColor: ink)!]))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        c.textPosition = CGPoint(x: -width / 2, y: -26)
        CTLineDraw(line, c)
        c.restoreGState()
    }
    // A star in the middle.
    c.setFillColor(ink)
    c.move(to: CGPoint(x: center.x, y: center.y + 170))
    for point in 1..<10 {
        let angle = .pi / 2 + Double(point) * .pi / 5
        let radius = point % 2 == 0 ? 170.0 : 68.0
        c.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
    }
    c.fillPath()
    // Uneven ink.
    for _ in 0..<1800 {
        c.setFillColor(CGColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 0.55))
        c.fillEllipse(in: CGRect(x: .random(in: 200...1200, using: &random), y: .random(in: 200...1200, using: &random), width: 7, height: 7))
    }
    writeJPEG(c.makeImage()!, "seal-photo.jpg")
}

// A photo of a signature in blue ink: a made-up name in a handwriting font, slightly tilted.
do {
    let w = 1800, h = 700
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    paper(c, w, h)
    let font = NSFont(name: "SnellRoundhand-Bold", size: 260) ?? NSFont.systemFont(ofSize: 220)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "J. Morgan", attributes: [
        .font: font, .foregroundColor: NSColor(red: 0.10, green: 0.20, blue: 0.62, alpha: 1)]))
    c.saveGState()
    c.translateBy(x: 230, y: 230)
    c.rotate(by: 0.06)
    c.textPosition = .zero
    CTLineDraw(line, c)
    c.restoreGState()
    c.setStrokeColor(CGColor(red: 0.10, green: 0.20, blue: 0.62, alpha: 1))
    c.setLineCap(.round); c.setLineWidth(8)
    c.move(to: CGPoint(x: 250, y: 190))
    c.addCurve(to: CGPoint(x: 1550, y: 260), control1: CGPoint(x: 700, y: 120), control2: CGPoint(x: 1200, y: 320))
    c.strokePath()
    writeJPEG(c.makeImage()!, "signature-photo.jpg")
}

// qr-invoice.pdf: an invoice with a payment link that imitates PayPal and an order note; qr-wifi.png.
do {
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let ctx = CGContext(URL(fileURLWithPath: "\(out)/qr-invoice.pdf") as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    text(texts.invoice, ctx, x: 50, y: 770, size: 28, weight: .bold)
    text(texts.scanToPay, ctx, x: 50, y: 700, size: 13)
    ctx.interpolationQuality = .none
    ctx.draw(qr("https://paypa1.com/pay?invoice=4471"), in: CGRect(x: 50, y: 480, width: 190, height: 190))
    ctx.draw(qr(texts.orderNote), in: CGRect(x: 300, y: 480, width: 190, height: 190))
    ctx.endPDFPage()
    ctx.closePDF()
    try! NSBitmapImageRep(cgImage: qr("WIFI:T:WPA;S:\(texts.wifiName);P:pine-and-lumen-24;;")).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "\(out)/qr-wifi.png"))
}
print("Demo files in \(out)")
