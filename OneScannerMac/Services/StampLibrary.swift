import AppKit
import Foundation
import Observation
import os

/// The saved signatures and stamps: PNGs with transparent paper and an index, only on this Mac, in the app's own
/// Application Support folder. Never uploaded; delete any time. Files already saved keep their stamps.
@MainActor
@Observable
final class StampLibrary {
    private(set) var stamps: [StampRecord] = []
    private(set) var images: [UUID: NSImage] = [:]
    var errorMessage: String?

    let folder: URL

    init(folder: URL = StampLibrary.defaultFolder) {
        self.folder = folder
        load()
    }

    nonisolated static var defaultFolder: URL {
        #if DEBUG
        // `-isolatedStamps YES` (QA and website screenshots): a throwaway library, never the person's own.
        if UserDefaults.standard.bool(forKey: "isolatedStamps") {
            return DebugLaunch.qaRoot.appendingPathComponent("stamps", isDirectory: true)
        }
        #endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("1Scanner/Stamps", isDirectory: true)
        SandboxMigration.run(stampsFolder: folder)
        return folder
    }

    private var indexURL: URL { folder.appendingPathComponent("stamps.json") }

    func fileURL(_ id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).png") }

    /// The PNG of every stamp, for writing files.
    var files: [UUID: URL] {
        Dictionary(uniqueKeysWithValues: stamps.map { ($0.id, fileURL($0.id)) })
    }

    func record(_ id: UUID) -> StampRecord? { stamps.first { $0.id == id } }

    /// The index is a few hundred bytes; images load as they are shown.
    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let saved = try? JSONDecoder().decode([StampRecord].self, from: data) else { return }
        stamps = saved.filter { FileManager.default.fileExists(atPath: fileURL($0.id).path) }
        for stamp in stamps { images[stamp.id] = NSImage(contentsOf: fileURL(stamp.id)) }
    }

    /// "Signature" for a wide image, "Stamp" otherwise; numbered when the name is taken.
    func suggestedName(for stamp: StampMaker.Stamp) -> String {
        let base = Double(stamp.pixelWidth) / Double(max(stamp.pixelHeight, 1)) >= 1.6
            ? String(localized: "Signature")
            : String(localized: "Stamp")
        let taken = Set(stamps.map(\.name))
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    /// Saves a new stamp; `id` is fixed for ready stamps, so the same one is written once.
    @discardableResult
    func add(_ stamp: StampMaker.Stamp, name: String, id: UUID = UUID()) -> StampRecord? {
        if let existing = record(id) { return existing }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = StampRecord(id: id, name: trimmed.isEmpty ? suggestedName(for: stamp) : trimmed,
                                 createdAt: Date(), pixelWidth: stamp.pixelWidth, pixelHeight: stamp.pixelHeight)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try stamp.png.write(to: fileURL(id), options: .atomic)
            try write(stamps + [record])
            stamps.append(record)
            images[id] = NSImage(data: stamp.png)
            return record
        } catch {
            try? FileManager.default.removeItem(at: fileURL(id))
            errorMessage = String(localized: "The signature or stamp couldn't be saved. Try again.")
            return nil
        }
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = stamps.firstIndex(where: { $0.id == id }) else { return }
        var updated = stamps
        updated[index].name = trimmed
        do {
            try write(updated)
            stamps = updated
        } catch {
            errorMessage = String(localized: "The change couldn't be saved. Try again.")
        }
    }

    /// Stamps already placed on open pages disappear from them too; saved files keep theirs.
    func delete(_ id: UUID) {
        let remaining = stamps.filter { $0.id != id }
        do {
            try write(remaining)
            try? FileManager.default.removeItem(at: fileURL(id))
            stamps = remaining
            images[id] = nil
        } catch {
            errorMessage = String(localized: "The change couldn't be saved. Try again.")
        }
    }

    private func write(_ records: [StampRecord]) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: indexURL, options: .atomic)
    }
}

/// 1.0.0 ran in the App Sandbox, so its signatures, stamps and settings live in its container. From 1.0.1 the app
/// isn't sandboxed (Install and Relaunch needs it); the first launch copies them over once. The
/// container is left as it was, so nothing can be lost.
enum SandboxMigration {
    private static let started = OSAllocatedUnfairLock(initialState: false)

    static func run(stampsFolder: URL) {
        guard started.withLock({ started in defer { started = true }; return !started }) else { return }
        let fileManager = FileManager.default
        let container = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Containers/app.antosha.onescanner.mac/Data/Library", isDirectory: true)
        // Signatures and stamps, only into an empty library.
        let oldStamps = container.appendingPathComponent("Application Support/Stamps", isDirectory: true)
        if fileManager.fileExists(atPath: oldStamps.appendingPathComponent("stamps.json").path),
           !fileManager.fileExists(atPath: stampsFolder.appendingPathComponent("stamps.json").path) {
            // Copied next to it first and put in place whole, so a failed copy never looks like a finished one; it is
            // tried again on the next launch. rename(2) replaces only a missing or empty folder.
            let parent = stampsFolder.deletingLastPathComponent()
            let staging = parent.appendingPathComponent(".Stamps-copying-" + UUID().uuidString.prefix(8), isDirectory: true)
            do {
                try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                try fileManager.copyItem(at: oldStamps, to: staging)
                guard rename(staging.path, stampsFolder.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
            } catch {
                try? fileManager.removeItem(at: staging)
            }
        }
        // Settings (the last size limit, whether support was offered…): keys this copy doesn't have yet.
        let oldDefaults = container.appendingPathComponent("Preferences/app.antosha.onescanner.mac.plist")
        if let saved = NSDictionary(contentsOf: oldDefaults) as? [String: Any] {
            let defaults = UserDefaults.standard
            for (key, value) in saved where defaults.object(forKey: key) == nil && !key.hasPrefix("NS") {
                defaults.set(value, forKey: key)
            }
        }
    }
}
