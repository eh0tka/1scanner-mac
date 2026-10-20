import SwiftUI

/// Merge PDFs: drop files or add open ones, drag rows into order, Merge… saves one PDF.
struct MergeView: View {
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Merge PDFs").font(.app(24, weight: .bold))
                    Text("Drop PDFs and images here, drag them into order, then Merge. Open files join as they are now, with their turns, removed pages and stamps.")
                        .font(.app(13))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(3)
                }
                .layoutPriority(1)
                Spacer(minLength: 20)
                Menu {
                    Button("Add Files…") {
                        let urls = model.chooseFiles()
                        Task { await model.addToMerge(urls) }
                    }
                    if !model.files.isEmpty {
                        Divider()
                        ForEach(model.files) { file in
                            Button(file.name) { model.merge.add(file) }
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuStyle(.button)
                .fixedSize()
            }

            if model.merge.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.down.right")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("Drop files to merge").font(.app(16, weight: .semibold))
                    Text("Two or more PDFs or images").font(.app(12.5)).foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isTargeted ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isTargeted ? Theme.accent : Theme.hairline, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(model.merge.items.enumerated()), id: \.element.id) { index, item in
                            MergeRow(item: item, number: index + 1)
                                .draggable(item.id.uuidString) {
                                    Text(item.name).font(.app(13, weight: .medium)).padding(8)
                                }
                                .dropDestination(for: String.self) { ids, _ in
                                    guard let id = ids.first.flatMap(UUID.init(uuidString:)),
                                          let from = model.merge.items.firstIndex(where: { $0.id == id }),
                                          let to = model.merge.items.firstIndex(where: { $0.id == item.id }), from != to else { return false }
                                    model.merge.move(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
                                    return true
                                }
                        }
                    }
                    .padding(12)
                }
                .background(isTargeted ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            HStack {
                Text(model.merge.items.isEmpty ? "" : String(localized: "\(model.merge.items.count) files") + " · " + String(localized: "\(model.merge.pageCount) pages"))
                    .font(.app(13))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                if !model.merge.items.isEmpty {
                    Button("Clear") { model.merge.items = [] }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button("Merge…") { model.mergeFiles() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.merge.items.count < 2 || model.busy != nil)
            }
        }
        .padding(28)
        .navigationTitle("Merge PDFs")
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task { await model.addToMerge(await DropLoader.urls(from: providers)) }
            return true
        }
    }
}

/// One file in the merge list: its number, first page, name and page count. Drag to reorder.
private struct MergeRow: View {
    @Environment(AppModel.self) private var model
    let item: MergeItem
    let number: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(Theme.secondaryText)
                .help("Drag to reorder")
            Text(verbatim: "\(number)")
                .font(.appNumber(13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 22)
            if let first = item.pages.first {
                PageImage(page: first, longSide: 120)
                    .frame(width: 44, height: 56)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.app(14, weight: .medium)).lineLimit(1)
                Text("\(item.pages.count) pages").font(.app(12)).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button {
                model.merge.items.removeAll { $0.id == item.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondaryText)
            .help("Remove from the list")
        }
        .padding(10)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }
}
