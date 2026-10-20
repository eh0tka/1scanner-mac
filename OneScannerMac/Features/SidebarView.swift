import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: Binding(get: { model.destination }, set: { model.destination = $0 })) {
            row("Home", systemImage: "house").tag(Destination.home)

            Section("Files") {
                ForEach(model.files) { file in
                    FileRow(file: file).tag(Destination.file(file.id))
                        .contextMenu {
                            Button("Save As…") { model.saveAs(file) }
                            Button("Add to Merge") {
                                model.merge.add(file)
                                model.destination = .merge
                            }
                            Divider()
                            Button("Close") { model.requestClose(file) }
                        }
                }
                Button {
                    let urls = model.chooseFiles()
                    Task { await model.open(urls) }
                } label: {
                    Label("Open…", systemImage: "plus")
                        .foregroundStyle(Theme.accentDeep)
                }
                .buttonStyle(.plain)
            }

            Section("Tools") {
                row("Merge PDFs", systemImage: "square.stack.3d.down.right").tag(Destination.merge)
                row("Signatures & Stamps", systemImage: "signature").tag(Destination.stamps)
                row("QR Codes", systemImage: "qrcode.viewfinder").tag(Destination.codes)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                BrandMark(size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text("1Scanner").font(.app(12, weight: .semibold))
                    Text("by 1Buck Apps").font(.app(10)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }
            .padding(12)
        }
    }

    private func row(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(Theme.accent)
        }
    }
}

private struct FileRow: View {
    @Environment(AppModel.self) private var model
    let file: OpenFile

    var body: some View {
        HStack(spacing: 6) {
            Label {
                Text(file.name).lineLimit(1).truncationMode(.middle)
            } icon: {
                Image(systemName: file.isPDF ? "doc.richtext" : "photo.on.rectangle")
                    .foregroundStyle(Theme.accent)
            }
            Spacer(minLength: 4)
            if file.isEdited {
                Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    .help("Not saved")
            }
            Text(verbatim: "\(file.pages.count)")
                .font(.appNumber(11, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .monospacedDigit()
            Button {
                model.requestClose(file)
            } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondaryText)
            .help("Close")
        }
    }
}
