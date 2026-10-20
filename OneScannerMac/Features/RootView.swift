import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var columns = Self.initialColumns
    @State private var isDropTargeted = false

    /// `-hideSidebar YES` (debug): opens without the sidebar, for snapshots taken while the screen is locked.
    private static var initialColumns: NavigationSplitViewVisibility {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "hideSidebar") { return .detailOnly }
        #endif
        return .all
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            Group {
                switch model.destination ?? .home {
                case .home: HomeView()
                case .file(let id):
                    if let file = model.file(id) {
                        if model.signingFileID == id {
                            SignView(file: file)
                        } else {
                            DocumentView(file: file)
                        }
                    } else {
                        HomeView()
                    }
                case .merge: MergeView()
                case .stamps: StampsView()
                case .codes: CodesView()
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .overlay(alignment: .bottom) { toastView }
            .animation(.easeOut(duration: 0.2), value: model.toast)
            .overlay { busyOverlay }
            .toolbar {
                // Always on screen, as in 1Cleaner for Mac: support and About.
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        model.support = .manual
                    } label: {
                        Label("Support 1Scanner", systemImage: "heart.fill")
                    }
                    .foregroundStyle(Theme.accent)
                    .help("Support the developer")
                    Button {
                        model.destination = .about
                    } label: {
                        Label("About 1Scanner", systemImage: "info.circle")
                    }
                    .help("About, updates, privacy and support")
                }
            }
        }
        .tint(Theme.accent)
        // Files dropped anywhere open, except on screens that take drops themselves.
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            Task {
                let urls = await DropLoader.urls(from: providers)
                await model.open(urls)
            }
            return true
        }
        .sheet(item: $model.support) { prompt in
            if prompt == .tellAFriend {
                TellAFriendView()
            } else {
                SupportView(afterResult: prompt == .afterFirstResult)
            }
        }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .compress(let id): if let file = model.file(id) { CompressSheet(file: file) }
            case .split(let id): if let file = model.file(id) { SplitSheet(file: file) }
            case .password(let id): if let file = model.file(id) { PasswordSheet(file: file) }
            case .exportImages(let id): if let file = model.file(id) { ExportImagesSheet(file: file) }
            }
        }
        .sheet(item: Binding(get: { model.passwordRequest }, set: { if $0 == nil { model.answerPassword(nil) } })) { request in
            PasswordPrompt(request: request)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("Save changes to “\(model.closingFile?.name ?? "")”?", isPresented: Binding(
            get: { model.closingFile != nil },
            set: { if !$0 { model.closingFile = nil } }
        ), presenting: model.closingFile) { file in
            Button("Save As…") {
                model.closingFile = nil
                model.saveAs(file)
            }
            Button("Don't Save", role: .destructive) { model.close(file) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Your changes will be lost if you close it without saving. The original file stays as it was.")
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = model.toast {
            HStack(spacing: 12) {
                Label(toast.text, systemImage: "checkmark.circle.fill")
                    .font(.app(13, weight: .medium))
                    .lineLimit(1)
                if let url = toast.reveal {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .buttonStyle(.link)
                        .font(.app(13, weight: .semibold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(Theme.hairline))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .padding(.bottom, 28)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var busyOverlay: some View {
        if let busy = model.busy {
            ZStack {
                Color.black.opacity(0.12).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text(busy.title).font(.app(14, weight: .semibold))
                    Button("Cancel") { busy.task?.cancel() }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(28)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 20, y: 6)
            }
        }
    }
}

/// File URLs from a drop.
@MainActor
enum DropLoader {
    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
            }
            if let url, url.isFileURL { urls.append(url) }
        }
        return urls
    }
}

/// The password of a locked PDF, asked while opening it.
struct PasswordPrompt: View {
    @Environment(AppModel.self) private var model
    let request: PasswordRequest
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("“\(request.fileName)” is locked", systemImage: "lock.fill")
                .font(.app(17, weight: .bold))
            Text(request.wasWrong
                 ? "That password didn't open it. Try again."
                 : "Enter its password to open it. The password stays on this Mac.")
                .font(.app(13))
                .foregroundStyle(request.wasWrong ? Theme.danger : Theme.secondaryText)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel") { model.answerPassword(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Open", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
    }

    private func submit() {
        guard !password.isEmpty else { return }
        model.answerPassword(password)
    }
}
