import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Where a new signature or stamp comes from.
enum StampSource: Identifiable {
    case file(URL)
    case data(Data)
    case drawing
    case ready

    var id: String {
        switch self {
        case .file(let url): "file-\(url.path)"
        case .data(let data): "data-\(data.count)-\(data.hashValue)"
        case .drawing: "drawing"
        case .ready: "ready"
        }
    }
}

/// The add buttons, shared by the library screen and the signing panel.
struct NewStampMenu: View {
    @Binding var source: StampSource?

    var body: some View {
        Menu {
            Button("From an Image File…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image]
                panel.message = String(localized: "Choose a photo or scan of your signature or stamp")
                if panel.runModal() == .OK, let url = panel.url { source = .file(url) }
            }
            Button("Draw with Trackpad or Mouse…") { source = .drawing }
            Button("Ready Stamps…") { source = .ready }
        } label: {
            Label("New Signature or Stamp", systemImage: "plus")
        }
    }
}

/// The library beside the page in Sign & Stamp: click to place; the selected stamp's actions below.
struct StampLibraryPanel: View {
    @Environment(AppModel.self) private var model
    let selected: StampPlacement?
    let onPlace: (StampRecord) -> Void
    let onRemoveSelected: () -> Void
    let onAddToAll: () -> Void
    let onRotate: (Double) -> Void
    @State private var source: StampSource?
    /// The slider's value; follows the selected stamp when it is turned on the page.
    @State private var angle: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Signatures & Stamps").font(.app(14, weight: .semibold))
                    if model.stamps.stamps.isEmpty {
                        Text("Add your signature or a company seal once; it stays in 1Scanner on this Mac for every document.")
                            .font(.app(12))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                        ForEach(model.stamps.stamps) { record in
                            Button { onPlace(record) } label: { StampTile(record: record, height: 64) }
                                .buttonStyle(.plain)
                                .help("Put on this page")
                        }
                    }
                    NewStampMenu(source: $source)
                        .menuStyle(.button)
                        .fixedSize()
                    Text("Or take a photo with your iPhone: File › Import from iPhone or iPad.")
                        .font(.app(11.5))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            if let selected {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.stamps.record(selected.stampID)?.name ?? "")
                        .font(.app(13, weight: .semibold))
                        .lineLimit(1)
                    HStack {
                        Text("Angle").font(.app(12)).foregroundStyle(Theme.secondaryText)
                        Slider(value: $angle, in: -180...180)
                            .onChange(of: angle) { _, value in
                                if abs(value - selected.rotation) > 0.01 { onRotate(value) }
                            }
                        Text(verbatim: "\(Int(selected.rotation.rounded()))°")
                            .font(.app(12)).monospacedDigit().frame(width: 38, alignment: .trailing)
                    }
                    Button(action: onAddToAll) {
                        Label("Add to All Pages", systemImage: "square.on.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button(role: .destructive, action: onRemoveSelected) {
                        Label("Remove from Page", systemImage: "trash")
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(Theme.danger)
                }
                .padding(16)
            }
        }
        .background(Theme.surface)
        .onChange(of: selected?.rotation, initial: true) { _, rotation in angle = rotation ?? 0 }
        .importsItemProviders([.image]) { providers in
            Task { if let data = await Self.imageData(from: providers) { source = .data(data) } }
            return true
        }
        .sheet(item: $source) { source in
            NewStampSheet(source: source) { record in onPlace(record) }
        }
    }

    static func imageData(from providers: [NSItemProvider]) async -> Data? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            let data: Data? = await withCheckedContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    continuation.resume(returning: data)
                }
            }
            if let data { return data }
        }
        return nil
    }
}

/// The library screen: every saved signature and stamp, rename and delete, add new ones.
struct StampsView: View {
    @Environment(AppModel.self) private var model
    @State private var source: StampSource?
    @State private var renaming: StampRecord?
    @State private var newName = ""
    @State private var deleting: StampRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Signatures & Stamps").font(.app(24, weight: .bold))
                        Text("""
                            Your signature, initials or a company seal, with the paper removed automatically. They stay \
                            only on this Mac. 1Scanner puts your own images on documents; it doesn't make a signature \
                            legally binding by itself.
                            """)
                            .font(.app(13))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 20)
                    NewStampMenu(source: $source)
                        .menuStyle(.button)
                        .fixedSize()
                }
                if model.stamps.stamps.isEmpty {
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("No signatures or stamps yet", systemImage: "signature")
                                .font(.app(15, weight: .semibold))
                            Text("""
                                Sign a white sheet of paper or stamp it, then take a photo with your iPhone (File › \
                                Import from iPhone or iPad) or choose a scan. You can also draw with the trackpad or \
                                pick a ready stamp like PAID or APPROVED.
                                """)
                                .font(.app(13))
                                .foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                    ForEach(model.stamps.stamps) { record in
                        VStack(alignment: .leading, spacing: 8) {
                            StampTile(record: record, height: 110)
                            HStack {
                                Text(record.name).font(.app(13, weight: .medium)).lineLimit(1)
                                Spacer()
                                Menu {
                                    Button("Rename…") {
                                        newName = record.name
                                        renaming = record
                                    }
                                    Button("Delete…", role: .destructive) { deleting = record }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .fixedSize()
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("Signatures & Stamps")
        .importsItemProviders([.image]) { providers in
            Task { if let data = await StampLibraryPanel.imageData(from: providers) { source = .data(data) } }
            return true
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task {
                if let url = await DropLoader.urls(from: providers).first(where: AppModel.isImage) { source = .file(url) }
            }
            return true
        }
        .sheet(item: $source) { source in
            NewStampSheet(source: source) { _ in }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let renaming { model.stamps.rename(renaming.id, to: newName) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { record in
            Button("Delete", role: .destructive) { model.deleteStamp(record.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It also leaves pages open in 1Scanner. Files you already saved keep it.")
        }
    }
}

/// A stamp on a checkerboard, so its transparent paper shows.
struct StampTile: View {
    @Environment(AppModel.self) private var model
    let record: StampRecord
    let height: CGFloat

    var body: some View {
        ZStack {
            Checkerboard()
            if let image = model.stamps.images[record.id] {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            for row in 0...Int(size.height / cell) {
                for column in 0...Int(size.width / cell) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                 with: .color(Color(white: 0.93)))
                }
            }
        }
    }
}

/// A new signature or stamp: the paper is removed, the result shown on a checkerboard and named before it's saved.
struct NewStampSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let source: StampSource
    let onSaved: (StampRecord) -> Void

    @State private var result: StampMaker.Stamp?
    @State private var preview: NSImage?
    @State private var name = ""
    @State private var errorText: String?
    @State private var work: Task<Void, Never>?
    @State private var drawingDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.app(18, weight: .bold))
            Group {
                if case .ready = source {
                    ReadyStampsPicker { record in
                        onSaved(record)
                        dismiss()
                    }
                } else if case .drawing = source, !drawingDone {
                    DrawingPad { data in
                        drawingDone = true
                        process { try await StampMaker.shared.makeStamp(from: data) }
                    }
                } else if let preview {
                    VStack(alignment: .leading, spacing: 12) {
                        ZStack {
                            Checkerboard()
                            Image(nsImage: preview).resizable().interpolation(.high).scaledToFit().padding(16)
                        }
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.hairline))
                        Text("The checkerboard is what stays transparent on the page.")
                            .font(.app(12))
                            .foregroundStyle(Theme.secondaryText)
                        TextField("Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                } else if let errorText {
                    NoteBanner(text: errorText, tone: .warning)
                } else {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Removing the paper…").font(.app(13)).foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    work?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                if result != nil {
                    Button("Save", action: save)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear(perform: start)
    }

    private var title: LocalizedStringKey {
        switch source {
        case .ready: "Ready Stamps"
        case .drawing: "Draw Your Signature"
        default: "New Signature or Stamp"
        }
    }

    private func start() {
        switch source {
        case .file(let url):
            process {
                _ = url.startAccessingSecurityScopedResource()
                return try await StampMaker.shared.makeStamp(fromFile: url)
            }
        case .data(let data):
            process { try await StampMaker.shared.makeStamp(from: data) }
        case .drawing, .ready:
            break
        }
    }

    private func process(_ make: @escaping @Sendable () async throws -> StampMaker.Stamp) {
        work = Task {
            do {
                let stamp = try await make()
                guard !Task.isCancelled else { return }
                result = stamp
                preview = NSImage(data: stamp.png)
                name = model.stamps.suggestedName(for: stamp)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func save() {
        guard let result, let record = model.stamps.add(result, name: name) else { return }
        onSaved(record)
        dismiss()
    }
}

/// Draw a signature with the trackpad or mouse; Use turns the strokes into a transparent image.
struct DrawingPad: View {
    let onUse: (Data) -> Void
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var ink: StampInk = .blue
    private let size = CGSize(width: 512, height: 220)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Canvas { context, _ in
                for stroke in strokes + [current] where stroke.count > 1 {
                    context.stroke(Self.path(stroke), with: .color(ink.color),
                                   style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: size.width, height: size.height)
            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.horizontal, 40).padding(.bottom, 50)
                    .allowsHitTesting(false)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in current.append(value.location) }
                    .onEnded { _ in
                        strokes.append(current)
                        current = []
                    }
            )
            HStack {
                Picker("Ink", selection: $ink) {
                    Text("Blue").tag(StampInk.blue)
                    Text("Black").tag(StampInk.black)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button("Clear") { strokes = [] }.disabled(strokes.isEmpty)
                Button("Use This Signature") { onUse(render()) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(strokes.isEmpty)
            }
        }
    }

    private static func path(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        // Smooth curves through the midpoints.
        for index in 1..<points.count {
            let mid = CGPoint(x: (points[index - 1].x + points[index].x) / 2, y: (points[index - 1].y + points[index].y) / 2)
            path.addQuadCurve(to: mid, control: points[index - 1])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    /// The strokes at 4× on a transparent background, as PNG.
    private func render() -> Data {
        let scale: CGFloat = 4
        let renderer = ImageRenderer(content:
            Canvas { context, _ in
                for stroke in strokes where stroke.count > 1 {
                    context.stroke(Self.path(stroke), with: .color(ink.color),
                                   style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: size.width, height: size.height)
        )
        renderer.scale = scale
        renderer.isOpaque = false
        guard let image = renderer.cgImage else { return Data() }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) ?? Data()
    }
}

/// APPROVED, PAID, COPY… in red, blue or black, with today's date if asked, or the person's own word.
struct ReadyStampsPicker: View {
    @Environment(AppModel.self) private var model
    let onChoose: (StampRecord) -> Void
    @AppStorage("readyStamps.ink") private var inkRaw = StampInk.red.rawValue
    @AppStorage("readyStamps.addDate") private var addDate = false
    @State private var previews: [String: NSImage] = [:]
    @State private var customWord = ""

    private var ink: StampInk { StampInk(rawValue: inkRaw) ?? .red }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("Color", selection: $inkRaw) {
                    ForEach(StampInk.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Toggle("Add today's date", isOn: $addDate)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(ReadyStamp.allCases) { stamp in
                    let word = stamp.word
                    let date = stamp == .date || addDate ? ReadyStampRenderer.today() : nil
                    Button { choose(word: word, date: date) } label: {
                        tile(key: "\(word ?? "")|\(date ?? "")|\(ink.rawValue)", word: word, date: date)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                TextField("Your own word, like PAID IN CASH", text: $customWord)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addCustom)
                Button("Add", action: addCustom)
                    .disabled(customWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func tile(key: String, word: String?, date: String?) -> some View {
        ZStack {
            Color.white
            if let image = previews[key] {
                Image(nsImage: image).resizable().scaledToFit().padding(10)
            }
        }
        .frame(height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline))
        .contentShape(Rectangle())
        .task(id: key) {
            guard previews[key] == nil else { return }
            let ink = ink
            let stamp = await Task.detached(priority: .userInitiated) {
                ReadyStampRenderer.render(word: word, date: date, ink: ink)
            }.value
            if let stamp { previews[key] = NSImage(data: stamp.png) }
        }
    }

    private func choose(word: String?, date: String?) {
        let ink = ink
        Task {
            let id = ReadyStampRenderer.stampID(word: word, date: date, ink: ink)
            if let existing = model.stamps.record(id) {
                onChoose(existing)
                return
            }
            guard let stamp = await Task.detached(priority: .userInitiated, operation: {
                ReadyStampRenderer.render(word: word, date: date, ink: ink)
            }).value else { return }
            let name = [word, date].compactMap { $0 }.joined(separator: " · ")
            if let record = model.stamps.add(stamp, name: name, id: id) { onChoose(record) }
        }
    }

    private func addCustom() {
        let word = String(customWord.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().prefix(40))
        guard !word.isEmpty else { return }
        choose(word: word, date: addDate ? ReadyStampRenderer.today() : nil)
    }
}
