import AppKit
import SwiftUI

/// QR Codes: drop or open pictures and PDFs, or paste a screenshot (⌘V). Every code found is shown with what it
/// holds; nothing opens by itself, and a link shows its real site and warnings before Open.
struct CodesView: View {
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("QR Codes").font(.app(24, weight: .bold))
                    Text("Read QR codes and barcodes from pictures, screenshots and every page of a PDF. Everything is read on this Mac.")
                        .font(.app(13))
                        .foregroundStyle(Theme.secondaryText)
                }
                dropZone
                if model.codes.isReading {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Reading…").font(.app(13)).foregroundStyle(Theme.secondaryText)
                        Button("Stop") { model.codes.task?.cancel() }.buttonStyle(.link)
                    }
                }
                if let message = model.codes.emptyMessage {
                    NoteBanner(text: message + " " + String(localized: "Try a sharper or larger picture."))
                }
                if !model.codes.found.isEmpty {
                    HStack {
                        Text("Found").font(.app(15, weight: .semibold))
                        Spacer()
                        Button("Clear") { model.codes.found = [] }.buttonStyle(.link)
                    }
                    ForEach(model.codes.found) { code in
                        CodeCard(code: code)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("QR Codes")
        .onPasteCommand(of: [.image, .png, .tiff]) { _ in model.readCodesFromClipboard() }
    }

    private var dropZone: some View {
        HStack(spacing: 18) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Drop a picture or PDF here").font(.app(16, weight: .semibold))
                Text("Or copy a screenshot (⌘⌃⇧4) and paste it with ⌘V.")
                    .font(.app(12.5))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button("Paste") { model.readCodesFromClipboard() }
                .buttonStyle(SecondaryButtonStyle())
            Button("Open…") {
                let urls = model.chooseFiles()
                if !urls.isEmpty { model.readCodes(from: urls) }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(22)
        .background(isTargeted ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isTargeted ? Theme.accent : Theme.hairline, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task { model.readCodes(from: await DropLoader.urls(from: providers)) }
            return true
        }
    }
}

/// One code: its kind, where it was found, what it holds and what can be done with it.
struct CodeCard: View {
    @Environment(AppModel.self) private var model
    let code: FoundCode

    var body: some View {
        let content = code.content
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: content.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 32, height: 32)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(content.kindTitle).font(.app(14, weight: .semibold))
                        Text(originLine).font(.app(11.5)).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Text(verbatim: code.symbology.displayName)
                        .font(.app(11, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.background, in: Capsule())
                }
                details(content)
            }
        }
    }

    private var originLine: String {
        if let page = code.page { return String(localized: "\(code.origin), page \(page)") }
        return code.origin
    }

    @ViewBuilder
    private func details(_ content: CodeContent) -> some View {
        switch content {
        case .link(let url):
            let check = LinkCheck(url: url, rawText: code.payload)
            VStack(alignment: .leading, spacing: 8) {
                Text(highlighted(check)).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                Label("Real site: \(check.realSite)", systemImage: "globe")
                    .font(.app(13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                ForEach(check.warnings, id: \.self) { warning in
                    NoteBanner(text: text(for: warning, realSite: check.realSite), tone: .warning)
                }
                HStack {
                    Button("Open in Browser") { NSWorkspace.shared.open(url) }
                        .buttonStyle(PrimaryButtonStyle())
                    copyButton(check.displayAddress, title: "Copy Link")
                }
            }
        case .wifi(let wifi):
            VStack(alignment: .leading, spacing: 8) {
                field("Network", wifi.ssid)
                if let password = wifi.password, !password.isEmpty {
                    field("Password", password)
                }
                HStack {
                    copyButton(wifi.ssid, title: "Copy Network Name")
                    if let password = wifi.password, !password.isEmpty {
                        copyButton(password, title: "Copy Password")
                    }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text(code.payload)
                    .font(.app(13))
                    .textSelection(.enabled)
                    .lineLimit(12)
                    .fixedSize(horizontal: false, vertical: true)
                copyButton(code.payload, title: "Copy")
            }
        }
    }

    private func field(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.app(11.5, weight: .semibold)).foregroundStyle(Theme.secondaryText)
            Text(value).font(.app(14, weight: .medium)).textSelection(.enabled)
        }
    }

    private func copyButton(_ text: String, title: LocalizedStringKey) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            model.showToast(String(localized: "Copied"))
        } label: {
            Label(title, systemImage: "doc.on.doc")
        }
        .buttonStyle(SecondaryButtonStyle())
    }

    /// The full address with the real site in bold red, so a site hidden in a long address stands out.
    private func highlighted(_ check: LinkCheck) -> AttributedString {
        var text = AttributedString(check.displayAddress)
        text.foregroundColor = Theme.secondaryText
        if let hostRange = text.range(of: check.host) {
            text[hostRange].foregroundColor = Theme.text
            if let siteRange = text[hostRange].range(of: check.realSite, options: .backwards) {
                text[siteRange].foregroundColor = Theme.accentDeep
                text[siteRange].font = .system(size: 13, weight: .bold, design: .monospaced)
            }
        }
        return text
    }

    private func text(for warning: LinkCheck.Warning, realSite: String) -> String {
        switch warning {
        case .plainHTTP:
            String(localized: "Not encrypted: the address starts with http, not https.")
        case .ipAddress:
            String(localized: "A bare number instead of a site name.")
        case .userInfo(let user):
            String(localized: "“\(user)” is not the site. The real site is \(realSite).")
        case .mixedScripts:
            String(localized: "Letters from different alphabets: this address can imitate another site.")
        case .internationalName:
            String(localized: "Special characters in the name can imitate another site.")
        case .lookalike(let brand):
            String(localized: "Looks like \(LinkCheck.brandName(brand)), but the real site is \(realSite).")
        case .brandInAddress(let brand, let site):
            String(localized: "The real site is \(site), not \(LinkCheck.brandName(brand)).")
        case .shortener:
            String(localized: "A short link hides where it leads.")
        }
    }
}
