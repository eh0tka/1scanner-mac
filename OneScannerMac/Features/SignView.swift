import AppKit
import SwiftUI

/// Sign & Stamp: one page large with its stamps, the pages on the left, the library on the right. A click on a
/// signature or stamp puts it on the page; drag it, pull the corner to resize, the top handle to turn. Stamps stay a
/// separate layer until Save As… draws them into the PDF.
struct SignView: View {
    @Environment(AppModel.self) private var model
    let file: OpenFile
    @State private var currentID: PageItem.ID?
    @State private var selectedPlacement: UUID?
    @FocusState private var pageFocused: Bool

    private var current: PageItem? {
        file.pages.first { $0.id == currentID } ?? file.pages.first
    }

    private var currentIndex: Int {
        current.flatMap { page in file.pages.firstIndex { $0.id == page.id } } ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                pageStrip
                Divider()
                pageArea
                Divider()
                StampLibraryPanel(selected: selectedStamp) { record in
                    place(record)
                } onRemoveSelected: {
                    removeSelected()
                } onAddToAll: {
                    if let current, let placement = selectedStamp { model.addToAllPages(placement, in: file, from: current.id) }
                } onRotate: { degrees in
                    guard let current, var placement = selectedStamp else { return }
                    placement.rotation = degrees
                    model.update(placement, on: file, page: current.id)
                }
                .frame(width: 280)
            }
        }
        .navigationTitle(file.name)
        .onAppear {
            currentID = model.signingStartPage ?? file.pages.first?.id
            pageFocused = true
            #if DEBUG
            // `-demoSelectStamp YES`: website screenshots show the handles of the page's last stamp.
            if UserDefaults.standard.bool(forKey: "demoSelectStamp") { selectedPlacement = current?.stamps.last?.id }
            #endif
        }
    }

    private var selectedStamp: StampPlacement? {
        current?.stamps.first { $0.id == selectedPlacement }
    }

    // MARK: Parts

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                model.signingFileID = nil
            } label: {
                Label("Pages", systemImage: "chevron.left")
            }
            .help("Back to all pages")
            VStack(alignment: .leading, spacing: 2) {
                Text("Sign & Stamp").font(.app(16, weight: .semibold))
                Text("Page \(currentIndex + 1) of \(file.pages.count)")
                    .font(.app(12))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            ControlGroup {
                Button { go(-1) } label: { Label("Previous Page", systemImage: "chevron.up") }
                    .disabled(currentIndex == 0)
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Button { go(1) } label: { Label("Next Page", systemImage: "chevron.down") }
                    .disabled(currentIndex >= file.pages.count - 1)
                    .keyboardShortcut(.downArrow, modifiers: .command)
            }
            .labelStyle(.iconOnly)
            .fixedSize()
            Button("Done") { model.signingFileID = nil }
                .buttonStyle(SecondaryButtonStyle())
            Button("Save As…") { model.saveAs(file) }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.surface)
    }

    private var pageStrip: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(Array(file.pages.enumerated()), id: \.element.id) { index, page in
                        VStack(spacing: 4) {
                            PageImage(page: page, longSide: 220, showsStamps: true)
                                .frame(height: 120)
                                .padding(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(page.id == current?.id ? Theme.accent : Color.clear, lineWidth: 2.5)
                                )
                            Text(verbatim: "\(index + 1)")
                                .font(.app(11, weight: page.id == current?.id ? .bold : .regular))
                                .foregroundStyle(page.id == current?.id ? Theme.accentDeep : Theme.secondaryText)
                        }
                        .id(page.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            currentID = page.id
                            selectedPlacement = nil
                        }
                    }
                }
                .padding(12)
            }
            .frame(width: 130)
            .onChange(of: currentID) { _, id in
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private var pageArea: some View {
        if let current {
            let key = Thumbnails.Key(source: current.source, turn: current.turn, longSide: 2000)
            ZStack {
                if let image = model.thumbnails.image(key) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .background(.white)
                        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
                        .overlay {
                            GeometryReader { proxy in
                                ZStack {
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedPlacement = nil }
                                    ForEach(current.stamps) { placement in
                                        PlacedStamp(placement: placement, pageSize: proxy.size,
                                                    isSelected: placement.id == selectedPlacement) {
                                            selectedPlacement = placement.id
                                            pageFocused = true
                                        } onChange: { updated in
                                            model.update(updated, on: file, page: current.id)
                                        }
                                    }
                                }
                                .coordinateSpace(.named(PlacedStamp.space))
                            }
                        }
                        .padding(28)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .task(id: key) { await model.thumbnails.load(key) }
            .focusable()
            .focusEffectDisabled()
            .focused($pageFocused)
            .onDeleteCommand(perform: removeSelected)
            .onExitCommand { selectedPlacement = nil }
        } else {
            Spacer()
        }
    }

    // MARK: Actions

    private func go(_ step: Int) {
        let index = min(max(currentIndex + step, 0), file.pages.count - 1)
        currentID = file.pages[index].id
        selectedPlacement = nil
    }

    private func place(_ record: StampRecord) {
        guard let current, let placement = model.place(record, on: file, page: current.id) else { return }
        selectedPlacement = placement.id
        pageFocused = true
    }

    private func removeSelected() {
        guard let current, let id = selectedPlacement else { return }
        model.remove(id, on: file, page: current.id)
        selectedPlacement = nil
    }
}

/// A stamp on the page being signed. Drag the stamp to move it; the corner handle resizes it (aspect kept); the
/// handle above turns it, snapping to straight angles. The handles are separate views placed at the turned stamp's
/// corners in the page's coordinate space, with a hit area larger than the dot, so a click lands where it looks.
struct PlacedStamp: View {
    static let space = "signPage"
    /// The visible dot and the area that takes the click.
    private static let dot: CGFloat = 20
    private static let hitArea: CGFloat = 36
    /// How far the turn handle sits above the stamp.
    private static let stemLength: CGFloat = 30

    @Environment(AppModel.self) private var model
    let placement: StampPlacement
    let pageSize: CGSize
    let isSelected: Bool
    let onSelect: () -> Void
    let onChange: (StampPlacement) -> Void
    @State private var start: StampPlacement?

    var body: some View {
        if let image = model.stamps.images[placement.stampID] {
            let aspect = image.size.width / max(image.size.height, 1)
            let width = placement.width * pageSize.width
            let height = width / max(aspect, 0.001)
            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: width, height: height)
                    .overlay {
                        if isSelected {
                            Rectangle()
                                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .padding(-4)
                        }
                    }
                    .contentShape(Rectangle())
                    .rotationEffect(.degrees(placement.rotation))
                    .qaFrame("stamp")
                    .gesture(move)
                    .onHover { inside in
                        if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
                    }
                    .position(centerPoint)
                if isSelected {
                    let top = point(dx: 0, dy: -height / 2 - 4)
                    let turnHandle = point(dx: 0, dy: -height / 2 - 4 - Self.stemLength)
                    Path { path in
                        path.move(to: top)
                        path.addLine(to: turnHandle)
                    }
                    .stroke(Theme.accent, lineWidth: 1.5)
                    .allowsHitTesting(false)
                    handle(systemImage: "arrow.clockwise", help: "Drag to turn")
                        .qaFrame("turn")
                        .position(turnHandle)
                        .gesture(rotate)
                    handle(systemImage: "arrow.up.left.and.arrow.down.right", help: "Drag to resize")
                        .qaFrame("resize")
                        .position(point(dx: width / 2 + 4, dy: height / 2 + 4))
                        .gesture(resize)
                }
            }
        }
    }

    private var centerPoint: CGPoint {
        CGPoint(x: placement.center.x * pageSize.width, y: placement.center.y * pageSize.height)
    }

    /// A point given relative to the stamp's center before turning, on the page after turning it (clockwise on screen).
    private func point(dx: CGFloat, dy: CGFloat) -> CGPoint {
        let angle = placement.rotation * .pi / 180
        return CGPoint(x: centerPoint.x + dx * cos(angle) - dy * sin(angle),
                       y: centerPoint.y + dx * sin(angle) + dy * cos(angle))
    }

    private func handle(systemImage: String, help: LocalizedStringKey) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: Self.dot, height: Self.dot)
            .background(Theme.accent, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
            .frame(width: Self.hitArea, height: Self.hitArea)
            .contentShape(Circle())
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .help(help)
    }

    /// Picks the stamp up at once (no click delay) and moves it; a click without moving just selects it.
    private var move: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if start == nil {
                    start = placement
                    onSelect()
                }
                guard let start else { return }
                var updated = placement
                updated.center = CGPoint(
                    x: min(max(start.center.x + value.translation.width / pageSize.width, 0), 1),
                    y: min(max(start.center.y + value.translation.height / pageSize.height, 0), 1)
                )
                if updated.center != placement.center { onChange(updated) }
            }
            .onEnded { _ in start = nil }
    }

    /// The stamp grows or shrinks with the pointer's distance from its center.
    private var resize: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if start == nil { start = placement }
                guard let start else { return }
                let center = CGPoint(x: start.center.x * pageSize.width, y: start.center.y * pageSize.height)
                let from = hypot(value.startLocation.x - center.x, value.startLocation.y - center.y)
                let to = hypot(value.location.x - center.x, value.location.y - center.y)
                guard from > 1 else { return }
                var updated = placement
                updated.width = min(max(start.width * to / from, 0.03), 1.2)
                onChange(updated)
            }
            .onEnded { _ in start = nil }
    }

    /// The stamp turns with the pointer around its center.
    private var rotate: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if start == nil { start = placement }
                guard let start else { return }
                let center = CGPoint(x: start.center.x * pageSize.width, y: start.center.y * pageSize.height)
                let from = atan2(value.startLocation.y - center.y, value.startLocation.x - center.x)
                let to = atan2(value.location.y - center.y, value.location.x - center.x)
                var degrees = start.rotation + (to - from) * 180 / .pi
                degrees = (degrees + 540).truncatingRemainder(dividingBy: 360) - 180
                // Straight angles are easy to hit.
                for straight in [-180.0, -90, 0, 90, 180] where abs(degrees - straight) < 4 { degrees = straight }
                var updated = placement
                updated.rotation = degrees
                onChange(updated)
            }
            .onEnded { _ in start = nil }
    }
}

extension View {
    /// DEBUG: records where a control is in the window, so headless QA can click it (`DebugLaunch`).
    func qaFrame(_ name: String) -> some View {
        #if DEBUG
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { QAProbe.frames[name] = $0 }
        #else
        self
        #endif
    }
}

#if DEBUG
@MainActor
enum QAProbe {
    static var frames: [String: CGRect] = [:]
}
#endif
