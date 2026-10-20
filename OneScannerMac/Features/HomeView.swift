import SwiftUI
import UniformTypeIdentifiers

/// Home: the brand, a big drop zone and the tools. Tools that work on one file ask for it first.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                dropZone
                tools
                Text("No ads. No tracking. No account.")
                    .font(.app(12.5, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("1Scanner")
    }

    private var header: some View {
        HStack(spacing: 14) {
            BrandMark(size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("1Scanner for Mac").font(.app(26, weight: .bold))
                Text("PDF tools, signatures and stamps, QR codes. Private by design · 100% on-device.")
                    .font(.app(13))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
        }
    }

    private var dropZone: some View {
        Button {
            let urls = model.chooseFiles()
            Task { await model.open(urls) }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Drop PDFs or images here").font(.app(18, weight: .semibold)).foregroundStyle(Theme.text)
                Text("or click to open. Images become pages of a new PDF.")
                    .font(.app(13))
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .background(isTargeted ? Theme.accentSoft : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isTargeted ? Theme.accent : Theme.hairline,
                                  style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task { await model.open(await DropLoader.urls(from: providers)) }
            return true
        }
    }

    private var tools: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
            tile("Sign & Stamp", detail: "Put your signature, initials or a company seal on any page, or on all of them.",
                 systemImage: "signature") { openOne(then: .sign) }
            tile("Compress", detail: "Original, Medium, Small, or up to the size a website or email asks for.",
                 systemImage: "arrow.down.right.and.arrow.up.left") { openOne(then: .compress) }
            tile("Merge PDFs", detail: "Join PDFs and images in the order you set.",
                 systemImage: "square.stack.3d.down.right") { model.destination = .merge }
            tile("Split", detail: "By page ranges like 1-3, 5, 8-10, every few pages or page by page.",
                 systemImage: "scissors") { openOne(then: .split) }
            tile("Read QR Codes", detail: "From pictures, screenshots and every page of a PDF.",
                 systemImage: "qrcode.viewfinder") { model.destination = .codes }
            tile("Images to PDF", detail: "Photos and scans as pages of one PDF, in name order.",
                 systemImage: "photo.on.rectangle.angled") {
                let urls = model.chooseFiles(types: [.image])
                Task { await model.open(urls) }
            }
        }
    }

    private func openOne(then tool: Tool) {
        let urls = model.chooseFiles(multiple: false, types: [.pdf])
        guard !urls.isEmpty else { return }
        Task { await model.open(urls, then: tool) }
    }

    private func tile(_ title: LocalizedStringKey, detail: LocalizedStringKey, systemImage: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.app(15, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(detail)
                        .font(.app(12.5))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
