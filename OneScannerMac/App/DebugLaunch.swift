import AppKit
import SwiftUI

/// DEBUG headless QA. QA files live in `qaRoot` (`-qaDir`, default `~/Library/Caches/app.antosha.onescanner.mac/qa`):
/// `in/` holds PDFs, images, `signature.*` and `qr*` files.
/// `-qa YES` opens them, signs, compresses, splits, merges, reads codes and exports pictures into `qa/out`, writes a
/// PNG per screen and `summary.txt` there, then quits. Originals are only read.
enum DebugLaunch {
    @MainActor
    static func apply(to model: AppModel) {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "qa") {
            Task { await run(model) }
        }
        // `-installUpdate YES -qaDir <dir>` (with `-updateFeed file:///…/version.json`): checks, installs the update and
        // relaunches; a failure is written to <dir>/install.txt.
        if UserDefaults.standard.bool(forKey: "installUpdate") {
            Task {
                let directory = qaRoot
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let report = directory.appendingPathComponent("install.txt")
                model.checkForUpdates()
                while model.isCheckingForUpdates { try? await Task.sleep(for: .milliseconds(200)) }
                guard case .available(let release) = model.updateResult else {
                    try? "no update: \(String(describing: model.updateResult))".write(to: report, atomically: true, encoding: .utf8)
                    exit(0)
                }
                // Stays "installing" when the copy relaunched (it quits right away); otherwise it holds the error.
                try? "installing".write(to: report, atomically: true, encoding: .utf8)
                model.installUpdate(release)
                while model.isInstallingUpdate { try? await Task.sleep(for: .milliseconds(200)) }
                if let error = model.updateInstallError {
                    try? error.write(to: report, atomically: true, encoding: .utf8)
                    exit(0)
                }
            }
            return
        }
        if UserDefaults.standard.bool(forKey: "demoShots") {
            Task { await demoShots(model) }
        }
        if UserDefaults.standard.bool(forKey: "qaStamp") {
            Task { await stampTest(model) }
        }
        // `-qaDocument YES`: the first PDF in qa/in, its screen at the narrowest window and at 1,600 pt wide.
        if UserDefaults.standard.bool(forKey: "qaDocument") {
            Task {
                let root = qaRoot
                let output = root.appendingPathComponent("out")
                try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let urls = ((try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("in"),
                                                                          includingPropertiesForKeys: nil)) ?? [])
                    .filter(AppModel.isPDF)
                await model.open(Array(urls.prefix(1)))
                guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { exit(1) }
                for width in [1000.0, 1600.0] {
                    window.setFrame(NSRect(x: 40, y: 40, width: width, height: 760), display: true)
                    try? await Task.sleep(for: .seconds(1.5))
                    writeImage(of: window, to: output.appendingPathComponent("document-\(Int(width)).png"))
                }
                exit(0)
            }
        }
        #endif
    }

    #if DEBUG
    /// QA files: `-qaDir <folder>`, or `~/Library/Caches/app.antosha.onescanner.mac/qa`.
    static var qaRoot: URL {
        if let path = UserDefaults.standard.string(forKey: "qaDir") { return URL(fileURLWithPath: path) }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.antosha.onescanner.mac/qa", isDirectory: true)
    }

    @MainActor
    private static func run(_ model: AppModel) async {
        let root = qaRoot
        let input = root.appendingPathComponent("in"), output = root.appendingPathComponent("out")
        try? FileManager.default.removeItem(at: output)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var summary = ""
        func log(_ line: String) { summary += line + "\n" }
        func shot(_ name: String) async {
            try? await Task.sleep(for: .milliseconds(1200))
            if let sheet = NSApp.windows.compactMap(\.attachedSheet).first {
                writeImage(of: sheet, to: output.appendingPathComponent("\(name).png"))
            } else if let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) {
                writeImage(of: window, to: output.appendingPathComponent("\(name).png"))
            }
        }

        // The one-time support offer and Tell a friend would cover later screens; they are shot on their own at the end.
        let restorePrompts = holdPrompts()
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .seconds(1))
        await shot("01-home")

        let files = ((try? FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let pdfs = files.filter { AppModel.isPDF($0) && !$0.lastPathComponent.hasPrefix("qr") }
        log("inputs: \(files.map(\.lastPathComponent))")

        // Open every PDF; the first is the one we work on.
        await model.open(pdfs)
        guard let file = model.files.first(where: { $0.url == pdfs.first }) else {
            log("no PDF opened")
            finish(summary, output)
            return
        }
        model.destination = .file(file.id)
        log("opened \(model.files.map { "\($0.name): \($0.pages.count) pages" })")
        if file.pages.count > 1 { file.selection = [file.pages[1].id] }
        await shot("02-document")

        // Stamps: from a photo of a signature, and a ready one.
        if let photo = files.first(where: { $0.lastPathComponent.hasPrefix("signature") }) {
            do {
                let stamp = try await StampMaker.shared.makeStamp(fromFile: photo)
                let record = model.stamps.add(stamp, name: "QA Signature")
                log("signature: \(stamp.pixelWidth)x\(stamp.pixelHeight) saved=\(record != nil)")
            } catch {
                log("signature failed: \(error.localizedDescription)")
            }
        }
        if let paid = ReadyStampRenderer.render(word: "PAID", date: ReadyStampRenderer.today(), ink: .blue) {
            _ = model.stamps.add(paid, name: "PAID", id: ReadyStampRenderer.stampID(word: "PAID", date: "qa", ink: .blue))
        }
        let signature = model.stamps.stamps.first { $0.name == "QA Signature" } ?? model.stamps.stamps.first
        let seal = model.stamps.stamps.first { $0.name == "PAID" }

        // Turn page 2 right, place the signature on page 1 and the PAID stamp on every page.
        if file.pages.count > 1 { model.turn(file, pages: [file.pages[1].id], clockwise: true) }
        try? await Task.sleep(for: .milliseconds(300))
        if let signature, var placed = model.place(signature, on: file, page: file.pages[0].id) {
            placed.center = CGPoint(x: 0.7, y: 0.85)
            placed.rotation = -8
            model.update(placed, on: file, page: file.pages[0].id)
        }
        if let seal, let placed = model.place(seal, on: file, page: file.pages[0].id) {
            model.addToAllPages(placed, in: file, from: file.pages[0].id)
        }
        model.signingStartPage = file.pages[0].id
        model.signingFileID = file.id
        await shot("03-sign")
        model.signingFileID = nil
        await shot("04-document-stamped")

        // Signed copy, compression ladder, Up to 0.5 MB.
        let engine = PDFEngine.shared
        do {
            let plan = model.plan(file.pages, password: file.password)
            let signed = try await engine.build(plan)
            try signed.write(to: output.appendingPathComponent("signed.pdf"))
            log("signed.pdf \(signed.count) bytes")
            for (name, step) in [("medium", Compression.medium), ("small", Compression.small)] {
                let data = try await engine.build(model.plan(file.pages, password: nil, quality: step))
                try data.write(to: output.appendingPathComponent("\(name).pdf"))
                log("\(name).pdf \(data.count) bytes")
            }
            let fit = try await Compression.fit(limit: 500_000) { step in
                try await engine.build(model.plan(file.pages, password: nil, quality: step))
            }
            try fit.data.write(to: output.appendingPathComponent("upto-0.5MB.pdf"))
            log("up to 0.5 MB: \(fit.data.count) bytes reached=\(fit.reached) pictures=\(fit.pagesAsPictures)")
            let locked = try await engine.build(model.plan(file.pages, password: "qa"))
            try locked.write(to: output.appendingPathComponent("password-qa.pdf"))
            log("password-qa.pdf \(locked.count) bytes")
            // Split 1-2 and the rest.
            if file.pages.count > 2, let ranges = PageRanges.parse("1-2, 3-\(file.pages.count)", count: file.pages.count) {
                for range in ranges {
                    let part = try await engine.build(model.plan(Array(file.pages[(range.lowerBound - 1)...(range.upperBound - 1)]), password: nil))
                    try part.write(to: output.appendingPathComponent("split \(range.lowerBound)-\(range.upperBound).pdf"))
                    log("split \(range): \(part.count) bytes")
                }
            }
            let pictures = try await engine.pictures(model.plan([file.pages[0]], password: nil), dpi: 100, jpeg: false)
            try pictures.first?.write(to: output.appendingPathComponent("page1.png"))
            log("page1.png \(pictures.first?.count ?? 0) bytes")
        } catch {
            log("build failed: \(error.localizedDescription)")
        }

        model.sheet = .compress(file.id)
        try? await Task.sleep(for: .seconds(4))
        await shot("05-compress")
        model.sheet = nil
        try? await Task.sleep(for: .seconds(1))
        model.sheet = .split(file.id)
        await shot("06-split")
        model.sheet = nil
        try? await Task.sleep(for: .seconds(2))

        // Merge every opened PDF.
        for opened in model.files { model.merge.add(opened) }
        model.destination = .merge
        await shot("07-merge")
        do {
            let merged = try await engine.build(model.plan(model.merge.items.flatMap(\.pages), password: nil))
            try merged.write(to: output.appendingPathComponent("merged.pdf"))
            log("merged.pdf \(merged.count) bytes, \(model.merge.pageCount) pages")
        } catch {
            log("merge failed: \(error.localizedDescription)")
        }

        // Codes from pictures and PDFs named qr*.
        let codeFiles = files.filter { $0.lastPathComponent.hasPrefix("qr") }
        model.destination = .codes
        model.readCodes(from: codeFiles)
        await model.codes.task?.value
        for code in model.codes.found {
            log("code \(code.symbology.displayName) \(code.origin) p\(code.page.map(String.init) ?? "-"): \(code.payload)")
        }
        if let empty = model.codes.emptyMessage { log("codes: \(empty)") }
        await shot("08-codes")

        model.destination = .stamps
        await shot("09-stamps")
        model.destination = .about
        await shot("10-about")
        model.support = .afterFirstResult
        await shot("11-support")
        model.support = nil
        try? await Task.sleep(for: .milliseconds(500))
        model.support = .tellAFriend
        await shot("12-tell-a-friend")
        model.support = nil
        // Leave this Mac's app as it was: no QA stamps in the library, the one-time support offer still pending.
        for stamp in model.stamps.stamps where stamp.name == "QA Signature" || stamp.name == "PAID" {
            model.stamps.delete(stamp.id)
        }
        restorePrompts()
        finish(summary, output)
    }

    /// `-qaStamp YES`: the first PDF in qa/in with `signature.*` placed on page 1: sizes of Original, Medium, Small
    /// and Up to 0.5 MB, then real mouse drags on the stamp, its resize handle and its turn handle.
    @MainActor
    private static func stampTest(_ model: AppModel) async {
        let root = qaRoot
        let input = root.appendingPathComponent("in"), output = root.appendingPathComponent("out")
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var log = ""
        let files = ((try? FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let pdf = files.first(where: AppModel.isPDF),
              let photo = files.first(where: { $0.lastPathComponent.hasPrefix("signature") }) else { exit(1) }
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .seconds(1))
        await model.open([pdf])
        guard let file = model.files.first,
              let stamp = try? await StampMaker.shared.makeStamp(fromFile: photo),
              let record = model.stamps.add(stamp, name: "QA Signature"),
              var placed = model.place(record, on: file, page: file.pages[0].id) else { exit(1) }
        let source = (try? pdf.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        log += "source \(source) bytes, stamp \(stamp.pixelWidth)x\(stamp.pixelHeight) png \(stamp.png.count)\n"
        let engine = PDFEngine.shared
        for (name, step) in [("original", nil), ("medium", Compression.medium), ("small", Compression.small)] as [(String, CompressionStep?)] {
            if let data = try? await engine.build(model.plan(file.pages, password: nil, quality: step)) {
                try? data.write(to: output.appendingPathComponent("stamp-\(name).pdf"))
                log += "\(name): \(data.count)\n"
            }
        }
        if let fit = try? await Compression.fit(limit: 200_000, build: { step in
            try await engine.build(model.plan(file.pages, password: nil, quality: step))
        }) {
            log += "up to 0.2 MB: \(fit.data.count) reached=\(fit.reached) pictures=\(fit.pagesAsPictures)\n"
            try? fit.data.write(to: output.appendingPathComponent("stamp-upto-0.2MB.pdf"))
        }
        if let fit = try? await Compression.fit(limit: 500_000, build: { step in
            try await engine.build(model.plan(file.pages, password: nil, quality: step))
        }) {
            log += "up to 0.5 MB: \(fit.data.count) reached=\(fit.reached) pictures=\(fit.pagesAsPictures)\n"
            try? fit.data.write(to: output.appendingPathComponent("stamp-upto-0.5MB.pdf"))
        }

        // Real mouse drags.
        model.signingStartPage = file.pages[0].id
        model.signingFileID = file.id
        model.destination = .file(file.id)
        try? await Task.sleep(for: .seconds(2))
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { exit(1) }
        // A first click into an inactive window only activates it, as for a person.
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(500))
        func state() -> String {
            let current = file.pages[0].stamps.first { $0.id == placed.id } ?? placed
            return String(format: "center %.3f,%.3f width %.3f rotation %.1f", current.center.x, current.center.y,
                          current.width, current.rotation)
        }
        func center(_ name: String) -> CGPoint? { QAProbe.frames[name].map { CGPoint(x: $0.midX, y: $0.midY) } }
        func drag(from: CGPoint, to: CGPoint) async {
            let height = window.contentView?.bounds.height ?? window.frame.height
            func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent? {
                NSEvent.mouseEvent(with: type, location: NSPoint(x: point.x, y: height - point.y), modifierFlags: [],
                                   timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            }
            if let down = event(.leftMouseDown, from) { window.sendEvent(down) }
            for step in 1...12 {
                let t = Double(step) / 12
                let point = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
                if let moved = event(.leftMouseDragged, point) { window.sendEvent(moved) }
                try? await Task.sleep(for: .milliseconds(16))
            }
            if let up = event(.leftMouseUp, to) { window.sendEvent(up) }
            try? await Task.sleep(for: .milliseconds(300))
        }
        log += "placed: \(state())\n"
        // Click the stamp to select it, so the handles appear.
        if let body = center("stamp") { await drag(from: body, to: body) }
        log += "after click: selected handles \(QAProbe.frames["resize"] != nil && QAProbe.frames["turn"] != nil)\n"
        if let body = center("stamp") {
            await drag(from: body, to: CGPoint(x: body.x - 60, y: body.y - 40))
            log += "after move (-60,-40): \(state())\n"
        }
        if let handle = center("resize") {
            // Grab the edge of the hit area, not the dot's middle: the click must still land.
            let grab = CGPoint(x: handle.x + 9, y: handle.y + 9)
            await drag(from: grab, to: CGPoint(x: grab.x + 50, y: grab.y + 50))
            log += "after resize (+50,+50): \(state())\n"
        }
        if let handle = center("turn"), let body = center("stamp") {
            // A quarter turn clockwise around the stamp's center.
            let radius = hypot(handle.x - body.x, handle.y - body.y)
            await drag(from: handle, to: CGPoint(x: body.x + radius, y: body.y))
            log += "after turn (quarter right): \(state())\n"
        }
        try? await Task.sleep(for: .milliseconds(600))
        writeImage(of: window, to: output.appendingPathComponent("stamp-handles.png"))
        placed = file.pages[0].stamps.first ?? placed
        for stamp in model.stamps.stamps where stamp.name == "QA Signature" { model.stamps.delete(stamp.id) }
        try? log.write(to: output.appendingPathComponent("stamp.txt"), atomically: true, encoding: .utf8)
        exit(0)
    }

    /// `-demoShots YES -isolatedStamps YES -compressUpTo YES -demoSelectStamp YES`: website screenshots from the made-up files of
    /// `tools/make_demo_files.swift` in qa/in, at a 1,280 × 800 window, into qa/out/demo-*.png, then quits.
    @MainActor
    private static func demoShots(_ model: AppModel) async {
        let root = qaRoot
        let input = root.appendingPathComponent("in"), output = root.appendingPathComponent("out")
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        UserDefaults.standard.set(1_000_000, forKey: Compression.limitKey)
        // The one-time support offer and Tell a friend would cover the screens after the first result.
        let restorePrompts = holdPrompts()
        func file(_ name: String) -> URL { input.appendingPathComponent(name) }
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .seconds(1))
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { exit(1) }
        window.setFrame(NSRect(x: 60, y: 60, width: 1280, height: 800), display: true)
        window.makeKeyAndOrderFront(nil)
        func shot(_ name: String) async {
            try? await Task.sleep(for: .milliseconds(1500))
            writeImage(of: window, withSheet: true, to: output.appendingPathComponent("demo-\(name).png"))
        }
        await shot("home")

        // The library: a seal and a signature from photos, and a ready stamp in the app's language. Names are the
        // made-up company's and signer's, so every language's screenshots read naturally.
        var seal: StampRecord?, signature: StampRecord?
        if let made = try? await StampMaker.shared.makeStamp(fromFile: file("seal-photo.jpg")) {
            seal = model.stamps.add(made, name: "Lumen & Pine")
        }
        if let made = try? await StampMaker.shared.makeStamp(fromFile: file("signature-photo.jpg")) {
            signature = model.stamps.add(made, name: "J. Morgan")
        }
        let paidWord = ReadyStamp.paid.word ?? "PAID"
        if let paid = ReadyStampRenderer.render(word: paidWord, date: ReadyStampRenderer.today(), ink: .blue) {
            _ = model.stamps.add(paid, name: paidWord, id: ReadyStampRenderer.stampID(word: paidWord, date: "demo", ink: .blue))
        }

        // The agreement's name depends on the demo language (tools/demo_texts.json).
        let agreementFile = ((try? FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)) ?? [])
            .first { AppModel.isPDF($0) && !$0.lastPathComponent.hasPrefix("qr") } ?? file("Service Agreement.pdf")
        await model.open([agreementFile])
        guard let agreement = model.files.first else { exit(1) }
        // Initials-size signature on every page, a full one and the seal on the last page.
        let last = agreement.pages[agreement.pages.count - 1].id
        if let signature, var placed = model.place(signature, on: agreement, page: last) {
            placed.center = CGPoint(x: 0.25, y: 0.665)
            placed.width = 0.3
            model.update(placed, on: agreement, page: last)
        }
        var sealPlacement: StampPlacement?
        if let seal, var placed = model.place(seal, on: agreement, page: last) {
            placed.center = CGPoint(x: 0.42, y: 0.64)
            placed.width = 0.24
            placed.rotation = -12
            model.update(placed, on: agreement, page: last)
            sealPlacement = placed
        }
        agreement.selection = [agreement.pages[1].id]
        model.destination = .file(agreement.id)
        await shot("document")

        model.signingStartPage = last
        model.signingFileID = agreement.id
        try? await Task.sleep(for: .seconds(1))
        _ = sealPlacement
        await shot("sign")
        model.signingFileID = nil

        model.sheet = .compress(agreement.id)
        try? await Task.sleep(for: .seconds(6))
        await shot("compress")
        model.sheet = nil
        try? await Task.sleep(for: .seconds(1.5))
        agreement.selection = Set(agreement.pages.prefix(2).map(\.id))
        model.sheet = .split(agreement.id)
        await shot("split")
        model.sheet = nil
        try? await Task.sleep(for: .seconds(1.5))
        agreement.selection = []

        model.destination = .codes
        model.readCodes(from: [file("qr-invoice.pdf"), file("qr-wifi.png")])
        await model.codes.task?.value
        await shot("codes")

        model.destination = .stamps
        await shot("stamps")

        await model.addToMerge([agreementFile, file("qr-invoice.pdf")])
        model.destination = .merge
        await shot("merge")

        for stamp in model.stamps.stamps { model.stamps.delete(stamp.id) }
        restorePrompts()
        exit(0)
    }

    @MainActor
    private static func finish(_ summary: String, _ output: URL) {
        try? summary.write(to: output.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
        // Nothing here is meant to be kept: quit without the unsaved-changes question.
        exit(0)
    }

    /// Keeps the support offer and Tell a friend away during a run and gives this Mac's own state back afterwards.
    private static func holdPrompts() -> () -> Void {
        let defaults = UserDefaults.standard
        let keys = ["support.offeredAfterFirstResult", AppModel.savedFilesKey, AppModel.friendStateKey]
        let saved = keys.map { defaults.object(forKey: $0) }
        defaults.set(true, forKey: "support.offeredAfterFirstResult")
        defaults.set("done", forKey: AppModel.friendStateKey)
        return {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
    }

    /// The window with its open sheet drawn where it sits, as people see them.
    @MainActor
    private static func writeImage(of window: NSWindow, withSheet: Bool, to url: URL) {
        guard withSheet, let sheet = window.attachedSheet,
              let base = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                                                 [.boundsIgnoreFraming, .bestResolution]),
              let top = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(sheet.windowNumber),
                                                [.boundsIgnoreFraming, .bestResolution]) else {
            writeImage(of: window, to: url)
            return
        }
        let scale = CGFloat(base.width) / window.frame.width
        guard let context = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        // Dim the window like macOS does behind a sheet.
        context.setFillColor(CGColor(gray: 0, alpha: 0.12))
        context.fill(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        let frame = CGRect(x: (sheet.frame.minX - window.frame.minX) * scale, y: (sheet.frame.minY - window.frame.minY) * scale,
                           width: CGFloat(top.width), height: CGFloat(top.height))
        context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 40 * scale, color: CGColor(gray: 0, alpha: 0.35))
        context.draw(top, in: frame)
        guard let image = context.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }

    @MainActor
    private static func writeImage(of window: NSWindow, to url: URL) {
        if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                                               [.boundsIgnoreFraming, .bestResolution]),
           image.width > 1 {
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
            return
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
    #endif
}
