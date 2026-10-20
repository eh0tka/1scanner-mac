import AppKit
import SwiftUI

/// About 1Scanner (toolbar ⓘ): version and updates, policies, support, telling a friend, the line's channels and
/// other apps.
struct AboutView: View {
    @Environment(AppModel.self) private var model
    /// The language picked here; nil is "Same as macOS".
    @State private var language: String? = AppLanguage.chosen

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    BrandMark(size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("1Scanner for Mac").font(.app(24, weight: .bold))
                        Text("Version \(UpdateChecker.currentVersion) (\(UpdateChecker.currentBuild)) · by 1Buck Apps")
                            .font(.app(12.5))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                }

                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Updates").font(.app(15, weight: .semibold))
                            Spacer()
                            if model.isCheckingForUpdates { ProgressView().controlSize(.small) }
                            Button("Check for Updates") { model.checkForUpdates() }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(model.isCheckingForUpdates)
                        }
                        updateStatus
                    }
                }

                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Language").font(.app(15, weight: .semibold))
                            Spacer()
                            Picker("Language", selection: $language) {
                                Text("Same as macOS").tag(String?.none)
                                Divider()
                                ForEach(AppLanguage.all, id: \.code) { entry in
                                    Text(verbatim: entry.name).tag(Optional(entry.code))
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                            .onChange(of: language) { AppLanguage.choose(language) }
                        }
                        // The running app keeps its language until it starts again; never over unsaved changes.
                        if language != AppLanguage.launchChoice {
                            HStack {
                                Text(model.hasUnsavedChanges
                                     ? String(localized: "1Scanner switches to the new language after a restart. Save or close the files with changes first.")
                                     : String(localized: "1Scanner switches to the new language after a restart."))
                                    .font(.app(12.5))
                                    .foregroundStyle(Theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Button("Restart 1Scanner") { AppLanguage.relaunch() }
                                    .buttonStyle(PrimaryButtonStyle())
                                    .disabled(model.isInstallingUpdate || model.busy != nil || model.hasUnsavedChanges)
                            }
                        }
                    }
                }

                Panel {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Free, with optional support").font(.app(15, weight: .semibold))
                        HStack(alignment: .top) {
                            Text("""
                                No ads, no tracking, no account, no subscription. Everything runs on your Mac. If \
                                1Scanner helps, you can support the developer with crypto.
                                """)
                                .font(.app(12.5))
                                .foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 16)
                            Button {
                                model.support = .manual
                            } label: {
                                Label("Support", systemImage: "heart.fill")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }

                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tell a friend").font(.app(15, weight: .semibold))
                        HStack(alignment: .top) {
                            Text("""
                                1Scanner spends nothing on ads, so people telling people is how it grows. Share \
                                a link to its page; nothing is sent unless you choose where.
                                """)
                                .font(.app(12.5))
                                .foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 16)
                            ShareLink(item: UpdateChecker.pageURL,
                                      message: Text(TellAFriendView.message)) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }

                linksPanel("Help & legal", links: [
                    ("envelope", String(localized: "Write to Support"), "mailto:support@onebuckapps.com?subject=1Scanner%20for%20Mac"),
                    ("lock.shield", String(localized: "Privacy Policy"), "https://onebuckapps.com/1scanner-mac/privacy/"),
                    ("doc.text", String(localized: "Terms of Use"), "https://onebuckapps.com/terms/"),
                ])
                linksPanel("Follow us", links: [
                    ("play.rectangle", "YouTube", "https://www.youtube.com/@onebuckapps"),
                    ("music.note", "TikTok", "https://www.tiktok.com/@onebuckapps"),
                    ("paperplane", "Telegram", "https://t.me/onebuckapps"),
                    ("at", String(localized: "X (developer)", comment: "Link to the developer's account on X"),
                     "https://x.com/antontrantin"),
                ])
                linksPanel("More from 1Buck Apps", links: [
                    ("square.grid.2x2", String(localized: "Our other apps"), "https://onebuckapps.com/"),
                ])
            }
            .padding(28)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("About 1Scanner")
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch model.updateResult {
        case nil:
            Text("1Scanner checks only when you ask. It reads one file on onebuckapps.com and sends nothing about your Mac.")
                .font(.app(12.5))
                .foregroundStyle(Theme.secondaryText)
        case .upToDate:
            Label("You have the latest version.", systemImage: "checkmark.circle.fill")
                .font(.app(13, weight: .medium))
                .foregroundStyle(Theme.success)
        case .available(let release):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Version \(release.version) is available.", systemImage: "arrow.down.circle.fill")
                        .font(.app(13, weight: .semibold))
                        .foregroundStyle(Theme.accentDeep)
                    Spacer()
                    if model.isInstallingUpdate {
                        ProgressView().controlSize(.small)
                        Text("Downloading and checking the update…")
                            .font(.app(12.5))
                            .foregroundStyle(Theme.secondaryText)
                    } else if Updater.canInstallHere, Updater.dmgURL(of: release) != nil, model.updateInstallError == nil {
                        Button("Download") { NSWorkspace.shared.open(release.downloadURL) }
                            .buttonStyle(SecondaryButtonStyle())
                        Button("Install and Relaunch") { model.installUpdate(release) }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!model.canInstallUpdate)
                    } else {
                        Button("Download") { NSWorkspace.shared.open(release.downloadURL) }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
                if model.hasUnsavedChanges, !model.isInstallingUpdate, model.updateInstallError == nil {
                    Text("Save or close the files with changes first: 1Scanner restarts to finish the update.")
                        .font(.app(12.5))
                        .foregroundStyle(Theme.secondaryText)
                }
                if let error = model.updateInstallError {
                    Text(error)
                        .font(.app(12.5))
                        .foregroundStyle(Theme.danger)
                }
            }
        case .failed(let message):
            Text(message)
                .font(.app(12.5))
                .foregroundStyle(Theme.danger)
        }
    }

    /// Link titles arrive localized; network names (YouTube, TikTok, Telegram) stay as they are.
    private func linksPanel(_ title: LocalizedStringKey, links: [(icon: String, title: String, url: String)]) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.app(15, weight: .semibold))
                ForEach(links, id: \.url) { link in
                    if let url = URL(string: link.url) {
                        Link(destination: url) {
                            Label(link.title, systemImage: link.icon)
                                .font(.app(13.5))
                        }
                    }
                }
            }
        }
    }
}
