import AppKit
import Observation

/// Merge: files in the order they'll be joined. Open files join as they are now (turns, deleted pages, stamps).
struct MergeItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let pages: [PageItem]
    let url: URL
}

@MainActor
@Observable
final class MergeModel {
    var items: [MergeItem] = []

    var pageCount: Int { items.reduce(0) { $0 + $1.pages.count } }

    func add(_ file: OpenFile) {
        items.append(MergeItem(name: file.name, pages: file.pages.map { $0.duplicated() }, url: file.url))
    }

    func add(url: URL, pageCount: Int) {
        items.append(MergeItem(name: url.deletingPathExtension().lastPathComponent,
                               pages: (0..<pageCount).map { PageItem(source: PageSource(url: url, index: $0)) },
                               url: url))
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }
}

extension AppModel {
    /// Adds PDFs and images to the merge list (each image is one page).
    func addToMerge(_ urls: [URL]) async {
        for url in urls {
            if Self.isPDF(url) {
                guard let loaded = await load(url) else { continue }
                merge.add(url: url, pageCount: loaded.pageCount)
            } else if Self.isImage(url) {
                if case .opened = await PDFEngine.shared.open(url) { merge.add(url: url, pageCount: 1) }
            }
        }
    }

    func mergeFiles() {
        guard merge.items.count >= 2, let first = merge.items.first else { return }
        guard let url = chooseSaveURL(name: "\(first.name) (\(String(localized: "merged")))", near: first.url) else { return }
        let pages = merge.items.flatMap(\.pages).map { $0.duplicated() }
        write(plan(pages, password: nil), to: url, title: String(localized: "Merging…"))
    }
}

/// QR Codes: codes read from files and pasted pictures, newest first. Kept only while the app runs.
@MainActor
@Observable
final class CodesModel {
    var found: [FoundCode] = []
    var isReading = false
    /// The last read that found nothing, to say so.
    var emptyMessage: String?
    var task: Task<Void, Never>?
}

extension AppModel {
    func readCodes(from urls: [URL]) {
        codes.task?.cancel()
        codes.task = Task {
            codes.isReading = true
            codes.emptyMessage = nil
            defer { codes.isReading = false }
            var found: [FoundCode] = []
            for url in urls {
                guard Self.isPDF(url) || Self.isImage(url) else { continue }
                let count: Int
                if Self.isPDF(url) {
                    guard let loaded = await load(url) else { continue }
                    count = loaded.pageCount
                } else {
                    guard case .opened = await PDFEngine.shared.open(url) else { continue }
                    count = 1
                }
                do {
                    found += try await PDFEngine.shared.codes(in: url, pageCount: count, origin: url.lastPathComponent)
                } catch {
                    return
                }
            }
            finishReading(found, from: urls.count == 1 ? urls[0].lastPathComponent : nil)
        }
    }

    /// A picture from the clipboard (a screenshot copied with ⌘⌃⇧4, an image copied in a browser).
    func readCodesFromClipboard() {
        guard let image = NSImage(pasteboard: .general),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            errorMessage = String(localized: "There's no picture on the clipboard. Copy a screenshot or an image first.")
            return
        }
        let picture = SendableImage(cgImage: cgImage)
        codes.task?.cancel()
        codes.task = Task {
            codes.isReading = true
            codes.emptyMessage = nil
            defer { codes.isReading = false }
            let origin = String(localized: "Pasted image")
            let found = await Task.detached(priority: .userInitiated) {
                CodeReader.codes(in: picture.cgImage).map {
                    FoundCode(payload: $0.payload, symbology: $0.symbology, origin: origin, page: nil)
                }
            }.value
            finishReading(found, from: origin)
        }
    }

    private func finishReading(_ found: [FoundCode], from origin: String?) {
        guard !Task.isCancelled else { return }
        if found.isEmpty {
            codes.emptyMessage = origin.map { String(localized: "No codes found in “\($0)”.") }
                ?? String(localized: "No codes found.")
        } else {
            codes.found.insert(contentsOf: found, at: 0)
            offerSupportOnce()
        }
    }
}
