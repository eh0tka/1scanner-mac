import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// An open file: its pages in a grid. Click selects (⌘ adds, ⇧ extends), drag reorders, double-click signs.
/// Dropping PDFs or images on the grid adds their pages after the selection.
struct DocumentView: View {
    @Environment(AppModel.self) private var model
    let file: OpenFile
    @State private var isTargeted = false
    @State private var anchor: PageItem.ID?
    @FocusState private var gridFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 18)], spacing: 22) {
                    ForEach(Array(file.pages.enumerated()), id: \.element.id) { index, page in
                        PageCell(page: page, number: index + 1, isSelected: file.selection.contains(page.id))
                            .onTapGesture {
                                // One gesture, so a single click selects without waiting for a possible second.
                                if NSApp.currentEvent?.clickCount == 2 { sign(startingAt: page.id) } else { select(page.id) }
                            }
                            .draggable(page.id.uuidString) {
                                PageCell(page: page, number: index + 1, isSelected: true).frame(width: 120)
                            }
                            .dropDestination(for: String.self) { ids, _ in
                                dropPages(ids, before: page.id)
                            }
                            .contextMenu { pageMenu(page) }
                    }
                }
                .padding(24)
            }
            .background(isTargeted ? Theme.accentSoft : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { file.selection = [] }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                Task { await model.insertPages(into: file, from: await DropLoader.urls(from: providers)) }
                return true
            }
            .focusable()
            .focusEffectDisabled()
            .focused($gridFocused)
            .onDeleteCommand { model.delete(file, pages: file.selection) }
            .onCommand(#selector(NSResponder.selectAll(_:))) { file.selection = Set(file.pages.map(\.id)) }
            .onExitCommand { file.selection = [] }
            footer
        }
        .navigationTitle(file.name)
        .onAppear { gridFocused = true }
    }

    // MARK: Bars

    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.app(16, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(statusLine).font(.app(12)).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            .frame(minWidth: 120, alignment: .leading)
            Spacer(minLength: 12)
            ControlGroup {
                Button { model.turn(file, pages: targetIDs, clockwise: false) } label: {
                    Label("Rotate Left", systemImage: "rotate.left")
                }
                .help("Rotate left")
                Button { model.turn(file, pages: targetIDs, clockwise: true) } label: {
                    Label("Rotate Right", systemImage: "rotate.right")
                }
                .help("Rotate right")
                Button { model.delete(file, pages: file.selection) } label: {
                    Label("Delete Pages", systemImage: "trash")
                }
                .help("Delete the selected pages")
                .disabled(file.selection.isEmpty)
            }
            .controlGroupStyle(.navigation)
            .labelStyle(.iconOnly)
            .fixedSize()

            // The everyday tools as buttons; on a narrow window they shrink to icons (titles in their help).
            ViewThatFits(in: .horizontal) {
                toolButtons(titles: true)
                toolButtons(titles: false)
            }

            Menu {
                Button("Insert Pages from Files…") {
                    let urls = model.chooseFiles()
                    Task { await model.insertPages(into: file, from: urls) }
                }
                Button(file.selection.isEmpty ? "Extract All Pages…" : "Extract Selected Pages…") { model.extract(file) }
                Button("Export Pages as Images…") { model.sheet = .exportImages(file.id) }
                Divider()
                Button("Add to Merge") {
                    model.merge.add(file)
                    model.destination = .merge
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .labelStyle(.iconOnly)
            .fixedSize()
            .help("Insert, extract, export as images, merge")

            Button("Save As…") { model.saveAs(file) }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.surface)
    }

    private func toolButtons(titles: Bool) -> some View {
        HStack(spacing: 8) {
            toolButton("Sign & Stamp", systemImage: "signature", titles: titles) {
                sign(startingAt: file.selection.isEmpty ? nil : file.pages.first { file.selection.contains($0.id) }?.id)
            }
            toolButton("Compress", systemImage: "arrow.down.right.and.arrow.up.left", titles: titles) {
                model.sheet = .compress(file.id)
            }
            toolButton("Split", systemImage: "scissors", titles: titles) { model.sheet = .split(file.id) }
            toolButton("Password", systemImage: file.password == nil ? "lock" : "lock.fill", titles: titles) {
                model.sheet = .password(file.id)
            }
        }
        .fixedSize()
    }

    private func toolButton(_ title: LocalizedStringKey, systemImage: String, titles: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if titles {
                    Label(title, systemImage: systemImage)
                } else {
                    Label(title, systemImage: systemImage).labelStyle(.iconOnly)
                }
            }
            .lineLimit(1)
        }
        .buttonStyle(ToolButtonStyle())
        .help(title)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(Theme.secondaryText)
            Text("Drag to reorder. Drop PDFs or images to add pages. Save As… makes a new file; the original stays as it is.")
                .font(.app(11.5))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var statusLine: String {
        let pages = String(localized: "\(file.pages.count) pages")
        var parts = [pages]
        if !file.selection.isEmpty { parts.append(String(localized: "\(file.selection.count) selected")) }
        if file.password != nil { parts.append(String(localized: "password")) }
        if file.isEdited { parts.append(String(localized: "not saved")) }
        return parts.joined(separator: " · ")
    }

    /// The selection, or every page when nothing is selected.
    private var targetIDs: Set<PageItem.ID> {
        file.selection.isEmpty ? Set(file.pages.map(\.id)) : file.selection
    }

    @ViewBuilder
    private func pageMenu(_ page: PageItem) -> some View {
        let ids = file.selection.contains(page.id) ? file.selection : [page.id]
        Button("Rotate Left") { model.turn(file, pages: ids, clockwise: false) }
        Button("Rotate Right") { model.turn(file, pages: ids, clockwise: true) }
        Button("Sign & Stamp") { sign(startingAt: page.id) }
        Button("Extract…") {
            file.selection = ids
            model.extract(file)
        }
        Divider()
        Button("Delete", role: .destructive) { model.delete(file, pages: ids) }
    }

    // MARK: Actions

    private func select(_ id: PageItem.ID) {
        gridFocused = true
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if file.selection.contains(id) { file.selection.remove(id) } else { file.selection.insert(id) }
            anchor = id
        } else if flags.contains(.shift), let anchor,
                  let from = file.pages.firstIndex(where: { $0.id == anchor }),
                  let to = file.pages.firstIndex(where: { $0.id == id }) {
            file.selection = Set(file.pages[min(from, to)...max(from, to)].map(\.id))
        } else {
            file.selection = [id]
            anchor = id
        }
    }

    /// A dragged page (and the rest of the selection with it) goes before `target`.
    private func dropPages(_ strings: [String], before target: PageItem.ID) -> Bool {
        guard let first = strings.first.flatMap(UUID.init(uuidString:)) else { return false }
        let ids = file.selection.contains(first)
            ? file.pages.map(\.id).filter { file.selection.contains($0) }
            : [first]
        model.move(file, pages: ids, before: target)
        return true
    }

    private func sign(startingAt id: PageItem.ID?) {
        model.signingStartPage = id
        model.signingFileID = file.id
    }
}

/// A page picture with its number; stamps on it are drawn over the picture.
struct PageCell: View {
    @Environment(AppModel.self) private var model
    let page: PageItem
    let number: Int
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            PageImage(page: page, longSide: 360, showsStamps: true)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .padding(6)
                .background(isSelected ? Theme.accentSoft : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? Theme.accent : Color.clear, lineWidth: 2.5)
                )
            HStack(spacing: 4) {
                Text(verbatim: "\(number)")
                    .font(.app(12, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Theme.accentDeep : Theme.secondaryText)
                if !page.stamps.isEmpty {
                    Image(systemName: "signature").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.accent)
                        .help("Has signatures or stamps")
                }
            }
        }
        .contentShape(Rectangle())
    }
}

/// The page picture, fitted, with a soft shadow; stamps drawn on top when asked.
struct PageImage: View {
    @Environment(AppModel.self) private var model
    let page: PageItem
    let longSide: Int
    var showsStamps = false

    var body: some View {
        let key = Thumbnails.Key(source: page.source, turn: page.turn, longSide: longSide)
        Group {
            if let image = model.thumbnails.image(key) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .overlay {
                        if showsStamps && !page.stamps.isEmpty {
                            GeometryReader { proxy in
                                ForEach(page.stamps) { stamp in
                                    StampImage(placement: stamp, pageSize: proxy.size)
                                }
                            }
                        }
                    }
                    .background(.white)
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Theme.surface)
                    .aspectRatio(0.707, contentMode: .fit)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .task(id: key) { await model.thumbnails.load(key) }
    }
}

/// A placed stamp drawn at its spot on a page shown at `pageSize`.
struct StampImage: View {
    @Environment(AppModel.self) private var model
    let placement: StampPlacement
    let pageSize: CGSize

    var body: some View {
        if let image = model.stamps.images[placement.stampID] {
            let width = placement.width * pageSize.width
            let aspect = image.size.width / max(image.size.height, 1)
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: width, height: width / max(aspect, 0.001))
                .rotationEffect(.degrees(placement.rotation))
                .position(x: placement.center.x * pageSize.width, y: placement.center.y * pageSize.height)
                .allowsHitTesting(false)
        }
    }
}
