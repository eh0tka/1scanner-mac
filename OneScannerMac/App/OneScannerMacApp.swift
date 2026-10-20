import AppKit
import SwiftUI

@main
struct OneScannerMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    init() {
        // The language this run started with, before About can change the choice.
        _ = AppLanguage.launchChoice
    }

    var body: some Scene {
        Window("1Scanner", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1000, minHeight: 660)
                .preferredColorScheme(.light)
                .onAppear { appDelegate.model = model }
                .task { DebugLaunch.apply(to: model) }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    let urls = model.chooseFiles()
                    Task { await model.open(urls) }
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save As…") {
                    if let file = model.currentFile { model.saveAs(file) }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.currentFile == nil || model.busy != nil)
                Button("Close File") {
                    if let file = model.currentFile { model.requestClose(file) }
                }
                .disabled(model.currentFile == nil)
            }
            // File › Import from iPhone or iPad: take a photo of a signature or stamp (Signatures & Stamps).
            ImportFromDevicesCommands()
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    model.destination = .about
                    model.checkForUpdates()
                }
                Button("Support the Developer…") { model.support = .manual }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor weak var model: AppModel?
    /// Files opened from Finder before the window was ready.
    @MainActor private var pending: [URL] = []

    /// With unsaved changes the app keeps running when its window closes (the Dock icon opens it again); Quit asks.
    @MainActor
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(model?.hasUnsavedChanges ?? false)
    }

    /// Open With 1Scanner, and files dropped on the Dock icon.
    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let model else {
            pending += urls
            Task { @MainActor in
                while self.model == nil { try? await Task.sleep(for: .milliseconds(100)) }
                let urls = self.pending
                self.pending = []
                await self.model?.open(urls)
            }
            return
        }
        Task { await model.open(urls) }
    }

    /// Unsaved changes are never dropped silently.
    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Installing an update swaps the app in a moment and then starts the new copy itself.
        if model?.isInstallingUpdate == true { return .terminateCancel }
        guard let model, model.hasUnsavedChanges else { return .terminateNow }
        let alert = NSAlert()
        let names = model.files.filter(\.isEdited).map(\.name)
        alert.messageText = String(localized: "Quit without saving?")
        alert.informativeText = String(localized: "Changes in \(names.formatted(.list(type: .and))) aren't saved. Use Save As… to keep them.")
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.addButton(withTitle: String(localized: "Quit Anyway"))
        alert.buttons[1].hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
