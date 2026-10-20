import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

enum Destination: Hashable {
    case home
    case file(UUID)
    case merge
    case stamps
    case codes
    case about
}

/// Why the Support sheet is open: the toolbar heart, or the first file 1Scanner made or the first code it read
/// (once after the first useful action, as in 1Cleaner for Mac; never again after that).
enum SupportPrompt: Identifiable, Equatable {
    case manual
    case afterFirstResult
    case tellAFriend

    var id: Self { self }
}

/// A sheet over an open file.
enum FileSheet: Identifiable, Equatable {
    case compress(UUID)
    case split(UUID)
    case password(UUID)
    case exportImages(UUID)

    var id: String {
        switch self {
        case .compress(let id): "compress-\(id)"
        case .split(let id): "split-\(id)"
        case .password(let id): "password-\(id)"
        case .exportImages(let id): "export-\(id)"
        }
    }
}

/// What to do once a file picked from Home is open.
enum Tool: Equatable {
    case sign, split, compress
}

/// An open PDF, or images opened together as one new PDF. The original file is only read.
@MainActor
@Observable
final class OpenFile: Identifiable {
    let id = UUID()
    /// The opened file (the first image for images).
    let url: URL
    let name: String
    let isPDF: Bool
    var pages: [PageItem]
    /// The file's password, kept when saving unless changed in Password.
    var password: String?
    var isEdited = false
    var selection: Set<PageItem.ID> = []

    init(url: URL, name: String, isPDF: Bool, pages: [PageItem], password: String?) {
        self.url = url
        self.name = name
        self.isPDF = isPDF
        self.pages = pages
        self.password = password
    }

    var hasStamps: Bool { pages.contains { !$0.stamps.isEmpty } }

    /// Selected pages in file order; all pages when nothing is selected.
    var selectedPages: [PageItem] {
        let selected = pages.filter { selection.contains($0.id) }
        return selected.isEmpty ? pages : selected
    }
}

struct PasswordRequest: Identifiable {
    let id = UUID()
    let fileName: String
    let wasWrong: Bool
}

struct Toast: Equatable {
    let text: String
    /// Show in Finder.
    let reveal: URL?
}

/// The busy overlay: what runs and how to stop it.
struct BusyState {
    let title: String
    let task: Task<Void, Never>?
}

@MainActor
@Observable
final class AppModel {
    var destination: Destination? = .home
    private(set) var files: [OpenFile] = []
    let stamps = StampLibrary()
    let thumbnails = Thumbnails()
    var merge = MergeModel()
    var codes = CodesModel()

    var support: SupportPrompt?
    var sheet: FileSheet?
    var toast: Toast?
    var errorMessage: String?
    var busy: BusyState?
    /// The file whose pages are being signed (Sign & Stamp mode in its screen).
    var signingFileID: UUID?
    /// The page Sign & Stamp opens on (the first when nil).
    var signingStartPage: PageItem.ID?
    /// A file with unsaved changes waiting for Save… / Don't Save / Cancel before it closes.
    var closingFile: OpenFile?

    private(set) var passwordRequest: PasswordRequest?
    private var passwordContinuation: CheckedContinuation<String?, Never>?

    private(set) var isCheckingForUpdates = false
    private(set) var updateResult: UpdateChecker.Result?
    /// Install and Relaunch is downloading, checking or swapping the app; quitting waits for it.
    private(set) var isInstallingUpdate = false
    private(set) var updateInstallError: String?
    private var toastTask: Task<Void, Never>?

    private let engine = PDFEngine.shared
    private static let supportOfferedKey = "support.offeredAfterFirstResult"
    nonisolated static let savedFilesKey = "friend.savedFiles"
    /// nil: never asked; "later": asked once (comes back once, `friendReturnDays` later); "done": never again.
    nonisolated static let friendStateKey = "friend.state"
    private static let friendAskedAtKey = "friend.askedAt"
    private static let friendReturnDays = 30
    /// The support offer and Tell a friend never come in the same session.
    private var offeredSupportThisSession = false

    func file(_ id: UUID) -> OpenFile? { files.first { $0.id == id } }

    var currentFile: OpenFile? {
        if case .file(let id) = destination { return file(id) }
        return nil
    }

    var hasUnsavedChanges: Bool { files.contains(where: \.isEdited) }

    // MARK: Opening

    /// The Open panel: PDFs and images. Returns the picked files.
    func chooseFiles(multiple: Bool = true, types: [UTType] = [.pdf, .image]) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        panel.allowedContentTypes = types
        panel.message = String(localized: "Choose PDFs or images")
        return panel.runModal() == .OK ? panel.urls : []
    }

    /// Opens PDFs and images and shows the last one. Each PDF becomes its own file; images opened together become one
    /// new PDF, a page per image in name order. `tool` opens a tool on it afterwards (Home tiles).
    func open(_ urls: [URL], then tool: Tool? = nil) async {
        let pdfs = urls.filter(Self.isPDF)
        let images = urls.filter { !Self.isPDF($0) && Self.isImage($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        if urls.count > 0, pdfs.isEmpty, images.isEmpty {
            errorMessage = String(localized: "1Scanner opens PDFs and images.")
            return
        }
        var last: OpenFile?
        for url in pdfs {
            if let existing = files.first(where: { $0.url == url && $0.isPDF }) {
                last = existing
                continue
            }
            guard let loaded = await load(url) else { continue }
            let file = OpenFile(url: url, name: url.deletingPathExtension().lastPathComponent, isPDF: true,
                                pages: (0..<loaded.pageCount).map { PageItem(source: PageSource(url: url, index: $0)) },
                                password: loaded.password)
            files.append(file)
            last = file
        }
        if !images.isEmpty {
            var pages: [PageItem] = []
            for url in images {
                if case .opened = await engine.open(url) {
                    pages.append(PageItem(source: PageSource(url: url, index: 0)))
                } else {
                    errorMessage = String(localized: "“\(url.lastPathComponent)” can't be opened.")
                }
            }
            if let first = pages.first?.source.url {
                let file = OpenFile(url: first, name: first.deletingPathExtension().lastPathComponent, isPDF: false,
                                    pages: pages, password: nil)
                // A new PDF that exists only here until it is saved.
                file.isEdited = true
                files.append(file)
                last = file
            }
        }
        guard let last else { return }
        destination = .file(last.id)
        switch tool {
        case .sign: signingFileID = last.id
        case .split: sheet = .split(last.id)
        case .compress: sheet = .compress(last.id)
        case nil: break
        }
    }

    /// Opens a PDF in the engine, asking for its password while it's locked. Nil when it can't be opened or the
    /// person cancels.
    func load(_ url: URL) async -> (pageCount: Int, password: String?)? {
        var password: String?
        while true {
            switch await engine.open(url, password: password) {
            case .opened(let count):
                return (count, password)
            case .needsPassword:
                guard let answer = await askPassword(for: url.lastPathComponent, wasWrong: password != nil) else {
                    return nil
                }
                password = answer
            case .unreadable:
                errorMessage = String(localized: "“\(url.lastPathComponent)” can't be opened. It may be damaged or not a PDF.")
                return nil
            }
        }
    }

    private func askPassword(for name: String, wasWrong: Bool) async -> String? {
        await withCheckedContinuation { continuation in
            passwordContinuation = continuation
            passwordRequest = PasswordRequest(fileName: name, wasWrong: wasWrong)
        }
    }

    func answerPassword(_ password: String?) {
        passwordRequest = nil
        let continuation = passwordContinuation
        passwordContinuation = nil
        continuation?.resume(returning: password)
    }

    static func isPDF(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .pdf) == true
    }

    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .image) == true
    }

    // MARK: Closing

    func requestClose(_ file: OpenFile) {
        if file.isEdited {
            closingFile = file
        } else {
            close(file)
        }
    }

    func close(_ file: OpenFile) {
        closingFile = nil
        files.removeAll { $0.id == file.id }
        if signingFileID == file.id { signingFileID = nil }
        if destination == .file(file.id) { destination = files.last.map { .file($0.id) } ?? .home }
        // The engine keeps documents other open files or the merge list still use.
        let used = Set(files.flatMap { $0.pages.map(\.source.url) } + merge.items.flatMap { $0.pages.map(\.source.url) })
        let urls = Set(file.pages.map(\.source.url)).subtracting(used)
        Task { for url in urls { await engine.forget(url) } }
    }

    // MARK: Page edits

    func turn(_ file: OpenFile, pages ids: Set<PageItem.ID>, clockwise: Bool) {
        guard !ids.isEmpty else { return }
        let pages = file.pages.filter { ids.contains($0.id) }
        Task {
            // Page sizes first (the engine knows them), then every change at once.
            var sizes: [PageItem.ID: CGSize] = [:]
            for page in pages where !page.stamps.isEmpty {
                sizes[page.id] = await engine.displaySize(page.source, turn: page.turn)
            }
            for index in file.pages.indices where ids.contains(file.pages[index].id) {
                var page = file.pages[index]
                // Stamps turn with the page: three quarter turns for one to the left.
                var size = sizes[page.id] ?? .zero
                for _ in 0..<(clockwise ? 1 : 3) {
                    page.stamps = page.stamps.map { $0.turnedClockwise(oldSize: size) }
                    page.turn = Normalized.angle(page.turn + 90)
                    size = CGSize(width: size.height, height: size.width)
                }
                file.pages[index] = page
            }
            file.isEdited = true
        }
    }

    func delete(_ file: OpenFile, pages ids: Set<PageItem.ID>) {
        guard !ids.isEmpty, ids.count < file.pages.count else {
            errorMessage = String(localized: "A file needs at least one page. To get rid of it, close the file.")
            return
        }
        file.pages.removeAll { ids.contains($0.id) }
        file.selection.subtract(ids)
        file.isEdited = true
    }

    /// Moves `ids` (in their current order) before `target`, or to the end when `target` is nil.
    func move(_ file: OpenFile, pages ids: [PageItem.ID], before target: PageItem.ID?) {
        let moving = file.pages.filter { ids.contains($0.id) }
        guard !moving.isEmpty, target.map({ !ids.contains($0) }) ?? true else { return }
        var remaining = file.pages.filter { !ids.contains($0.id) }
        let index = target.flatMap { id in remaining.firstIndex { $0.id == id } } ?? remaining.endIndex
        remaining.insert(contentsOf: moving, at: index)
        guard remaining.map(\.id) != file.pages.map(\.id) else { return }
        file.pages = remaining
        file.isEdited = true
    }

    /// Inserts the pages of other PDFs and images after the selection (or at the end).
    func insertPages(into file: OpenFile, from urls: [URL]) async {
        var added: [PageItem] = []
        for url in urls {
            if Self.isPDF(url) {
                guard let loaded = await load(url) else { continue }
                added += (0..<loaded.pageCount).map { PageItem(source: PageSource(url: url, index: $0)) }
            } else if Self.isImage(url), case .opened = await engine.open(url) {
                added.append(PageItem(source: PageSource(url: url, index: 0)))
            }
        }
        guard !added.isEmpty else { return }
        let after = file.pages.lastIndex { file.selection.contains($0.id) }.map { $0 + 1 } ?? file.pages.endIndex
        file.pages.insert(contentsOf: added, at: after)
        file.selection = Set(added.map(\.id))
        file.isEdited = true
    }

    // MARK: Stamps on pages

    func place(_ stamp: StampRecord, on file: OpenFile, page id: PageItem.ID) -> StampPlacement? {
        guard let index = file.pages.firstIndex(where: { $0.id == id }) else { return nil }
        // A signature a third of the page wide, a stamp a quarter; a little below the middle.
        let width = stamp.aspect >= 1.6 ? 0.34 : 0.24
        let offset = Double(file.pages[index].stamps.count % 5) * 0.04
        let placement = StampPlacement(stampID: stamp.id, center: CGPoint(x: 0.5 + offset, y: 0.62 + offset), width: width)
        file.pages[index].stamps.append(placement)
        file.isEdited = true
        return placement
    }

    func update(_ placement: StampPlacement, on file: OpenFile, page id: PageItem.ID) {
        guard let index = file.pages.firstIndex(where: { $0.id == id }),
              let stampIndex = file.pages[index].stamps.firstIndex(where: { $0.id == placement.id }) else { return }
        file.pages[index].stamps[stampIndex] = placement
        file.isEdited = true
    }

    func remove(_ placementID: UUID, on file: OpenFile, page id: PageItem.ID) {
        guard let index = file.pages.firstIndex(where: { $0.id == id }) else { return }
        file.pages[index].stamps.removeAll { $0.id == placementID }
        file.isEdited = true
    }

    /// The same stamp at the same spot on every other page (initials, a seal on each sheet).
    func addToAllPages(_ placement: StampPlacement, in file: OpenFile, from id: PageItem.ID) {
        for index in file.pages.indices where file.pages[index].id != id {
            file.pages[index].stamps.append(StampPlacement(stampID: placement.stampID, center: placement.center,
                                                           width: placement.width, rotation: placement.rotation))
        }
        file.isEdited = true
        showToast(String(localized: "Added to all \(file.pages.count) pages"))
    }

    /// A deleted library stamp leaves every open page too.
    func deleteStamp(_ id: UUID) {
        for file in files {
            for index in file.pages.indices where file.pages[index].stamps.contains(where: { $0.stampID == id }) {
                file.pages[index].stamps.removeAll { $0.stampID == id }
                file.isEdited = true
            }
        }
        stamps.delete(id)
    }

    // MARK: Saving

    func plan(_ pages: [PageItem], password: String?, quality: CompressionStep? = nil) -> BuildPlan {
        BuildPlan(pages: pages, stampFiles: stamps.files, password: password, quality: quality)
    }

    /// The Save panel in the original's folder. Nil when cancelled.
    func chooseSaveURL(name: String, near url: URL?) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = name.hasSuffix(".pdf") ? name : name + ".pdf"
        if let folder = url?.deletingLastPathComponent() { panel.directoryURL = folder }
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// The folder picker for files made in bulk (Split, page pictures).
    func chooseFolder(near url: URL?, prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        if let folder = url?.deletingLastPathComponent() { panel.directoryURL = folder }
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Files open in 1Scanner (and in the merge list) are read page by page while they're open, so a new file never
    /// replaces one of them.
    func isInUse(_ url: URL) -> Bool {
        let target = url.standardizedFileURL.resolvingSymlinksInPath()
        let used = files.flatMap { $0.pages.map(\.source.url) } + merge.items.flatMap { $0.pages.map(\.source.url) }
        return used.contains { $0.standardizedFileURL.resolvingSymlinksInPath() == target }
    }

    private func refuseInUse(_ url: URL) -> Bool {
        guard isInUse(url) else { return false }
        errorMessage = String(localized: "“\(url.lastPathComponent)” is open in 1Scanner, so it can't be replaced. Save under another name.")
        return true
    }

    /// Builds `plan` in the background with the busy overlay and Cancel, then writes it to `url`.
    func write(_ plan: BuildPlan, to url: URL, title: String, onSaved: @escaping @MainActor () -> Void = {}) {
        guard !refuseInUse(url) else { return }
        run(title) { [engine] in
            let data = try await engine.build(plan)
            try Task.checkCancellation()
            try await Self.write(data, to: url)
            onSaved()
            self.saved([url])
        }
    }

    /// Writes data off the main actor; the Save panel has granted access to that file.
    nonisolated static func write(_ data: Data, to url: URL) async throws {
        try await Task.detached(priority: .userInitiated) { try data.write(to: url) }.value
    }

    /// Runs work with the busy overlay; errors show as an alert, Cancel stops it quietly.
    func run(_ title: String, _ work: @escaping @MainActor () async throws -> Void) {
        guard busy == nil else { return }
        let task = Task { @MainActor in
            do {
                try await work()
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
            busy = nil
        }
        busy = BusyState(title: title, task: task)
    }

    /// The file(s) are on disk: a toast with Show in Finder, and the one-time support offer after the first result.
    func saved(_ urls: [URL]) {
        guard let first = urls.first else { return }
        let text = urls.count == 1
            ? String(localized: "Saved “\(first.lastPathComponent)”")
            : String(localized: "Saved \(urls.count) files")
        showToast(text, reveal: first)
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: Self.savedFilesKey) + urls.count, forKey: Self.savedFilesKey)
        offerSupportOnce()
        offerFriendIfDue()
    }

    func offerSupportOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.supportOfferedKey) else { return }
        defaults.set(true, forKey: Self.supportOfferedKey)
        offeredSupportThisSession = true
        // After the Save panel and the toast have settled.
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            if support == nil { support = .afterFirstResult }
        }
    }

    /// Tell a friend: from the third saved file, never in the session that offered support;
    /// shown once, and once more 30 days after a Not Now. Marked when shown, so an ignored sheet doesn't come back
    /// sooner.
    private func offerFriendIfDue() {
        let defaults = UserDefaults.standard
        guard !offeredSupportThisSession, defaults.integer(forKey: Self.savedFilesKey) >= 3 else { return }
        switch defaults.string(forKey: Self.friendStateKey) {
        case nil:
            defaults.set("later", forKey: Self.friendStateKey)
        case "later":
            guard let asked = defaults.object(forKey: Self.friendAskedAtKey) as? Date,
                  Date().timeIntervalSince(asked) >= Double(Self.friendReturnDays) * 86_400 else { return }
            defaults.set("done", forKey: Self.friendStateKey)
        default:
            return
        }
        defaults.set(Date(), forKey: Self.friendAskedAtKey)
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            if support == nil { support = .tellAFriend }
        }
    }

    /// Shared or copied: Tell a friend never comes back on its own.
    func friendShared() {
        UserDefaults.standard.set("done", forKey: Self.friendStateKey)
    }

    func showToast(_ text: String, reveal: URL? = nil) {
        toastTask?.cancel()
        toast = Toast(text: text, reveal: reveal)
        toastTask = Task {
            try? await Task.sleep(for: .seconds(reveal == nil ? 2.5 : 6))
            guard !Task.isCancelled else { return }
            toast = nil
        }
    }

    /// Save As… for an open file: its pages, turns, stamps and password, as a new PDF.
    func saveAs(_ file: OpenFile) {
        let suffix = file.isPDF ? (file.hasStamps ? String(localized: "signed") : String(localized: "edited")) : nil
        let name = suffix.map { "\(file.name) (\($0))" } ?? file.name
        guard let url = chooseSaveURL(name: name, near: file.url) else { return }
        write(plan(file.pages, password: file.password), to: url, title: String(localized: "Saving…")) {
            file.isEdited = false
        }
    }

    /// Ready data (a compressed copy) saved where the person chooses.
    func save(_ data: Data, name: String, near url: URL?) {
        guard let target = chooseSaveURL(name: name, near: url), !refuseInUse(target) else { return }
        run(String(localized: "Saving…")) {
            try await Self.write(data, to: target)
            self.saved([target])
        }
    }

    /// Several files into a folder the person picks, without replacing anything there ("Report 1-3 2.pdf").
    func writeFiles(_ parts: [(name: String, ext: String)], near url: URL?, prompt: String, title: String,
                    make: @escaping @MainActor (Int) async throws -> Data) {
        guard let folder = chooseFolder(near: url, prompt: prompt) else { return }
        run(title) {
            var written: [URL] = []
            for (index, part) in parts.enumerated() {
                try Task.checkCancellation()
                let data = try await make(index)
                let target = Self.freeURL(in: folder, name: part.name, ext: part.ext)
                try await Self.write(data, to: target)
                written.append(target)
            }
            self.saved(written)
        }
    }

    nonisolated static func freeURL(in folder: URL, name: String, ext: String) -> URL {
        var candidate = folder.appendingPathComponent(name).appendingPathExtension(ext)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name) \(number)").appendingPathExtension(ext)
            number += 1
        }
        return candidate
    }

    /// The selected pages as a new PDF.
    func extract(_ file: OpenFile) {
        let pages = file.selectedPages
        let numbers = PageRanges.describe(pages.compactMap { page in file.pages.firstIndex { $0.id == page.id }.map { $0 + 1 } })
        guard let url = chooseSaveURL(name: "\(file.name) (\(String(localized: "pages")) \(numbers))", near: file.url) else { return }
        write(plan(pages.map { $0.duplicated() }, password: file.password), to: url, title: String(localized: "Saving…"))
    }

    // MARK: Updates

    /// Not while a file is being made or files have unsaved changes: the new copy starts right away.
    var canInstallUpdate: Bool { !isInstallingUpdate && busy == nil && !hasUnsavedChanges }

    /// Install and Relaunch (as in 1Cleaner for Mac): only on the person's click.
    func installUpdate(_ release: UpdateChecker.Release) {
        guard canInstallUpdate else { return }
        isInstallingUpdate = true
        updateInstallError = nil
        Task {
            if let error = await Updater.install(release) {
                updateInstallError = error
                isInstallingUpdate = false
                return
            }
            // A file started or changed while the update downloaded keeps this copy running: never cut a save short.
            guard busy == nil, !hasUnsavedChanges else { return installedWithoutRelaunch() }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
                let opened = error == nil
                Task { @MainActor in
                    guard opened, self.busy == nil, !self.hasUnsavedChanges else { return self.installedWithoutRelaunch() }
                    // The new copy starts in place of this one: quitting may go on.
                    self.isInstallingUpdate = false
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func installedWithoutRelaunch() {
        updateInstallError = String(localized: "The update is installed. Save your files, then quit and open 1Scanner again to use it.")
        isInstallingUpdate = false
    }

    func checkForUpdates() {
        guard !isCheckingForUpdates, !isInstallingUpdate else { return }
        isCheckingForUpdates = true
        updateInstallError = nil
        updateResult = nil
        Task {
            updateResult = await UpdateChecker.check()
            isCheckingForUpdates = false
        }
    }
}

/// Page pictures for the grid and the signing view, made by the engine and kept while they are shown.
@MainActor
@Observable
final class Thumbnails {
    struct Key: Hashable {
        let source: PageSource
        let turn: Int
        let longSide: Int
    }

    private(set) var images: [Key: NSImage] = [:]
    @ObservationIgnored private var order: [Key] = []
    @ObservationIgnored private var loading: Set<Key> = []

    func image(_ key: Key) -> NSImage? { images[key] }

    func load(_ key: Key) async {
        guard images[key] == nil, !loading.contains(key) else { return }
        loading.insert(key)
        defer { loading.remove(key) }
        guard let picture = await PDFEngine.shared.image(key.source, turn: key.turn, longSide: CGFloat(key.longSide)) else { return }
        let image = picture.cgImage
        images[key] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        order.append(key)
        // Small pictures are cheap; big ones (signing) are kept only for a few pages.
        let big = order.filter { $0.longSide > 600 }
        if big.count > 6, let oldest = big.first { evict(oldest) }
        if order.count > 800, let oldest = order.first { evict(oldest) }
    }

    private func evict(_ key: Key) {
        images[key] = nil
        order.removeAll { $0 == key }
    }
}

/// "1-3, 5, 8-10" from page numbers.
enum PageRanges {
    static func describe(_ numbers: [Int]) -> String {
        let sorted = Array(Set(numbers)).sorted()
        var parts: [String] = []
        var index = 0
        while index < sorted.count {
            var end = index
            while end + 1 < sorted.count, sorted[end + 1] == sorted[end] + 1 { end += 1 }
            parts.append(end == index ? "\(sorted[index])" : "\(sorted[index])-\(sorted[end])")
            index = end + 1
        }
        return parts.joined(separator: ", ")
    }

    /// Parses "1-3, 5, 8-10" into ranges of page numbers (1-based), each within 1...count. Nil when anything is
    /// unreadable or out of range.
    static func parse(_ text: String, count: Int) -> [ClosedRange<Int>]? {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        var ranges: [ClosedRange<Int>] = []
        for part in parts {
            let bounds = part.split(whereSeparator: { $0 == "-" || $0 == "–" || $0 == "—" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard (1...2).contains(bounds.count), let first = Int(bounds[0]),
                  let last = bounds.count == 2 ? Int(bounds[1]) : first,
                  first >= 1, last <= count, first <= last else { return nil }
            ranges.append(first...last)
        }
        return ranges
    }
}
