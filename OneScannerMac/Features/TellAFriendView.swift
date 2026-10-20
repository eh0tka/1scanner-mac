import AppKit
import SwiftUI

/// "Tell a friend" (as in 1Scanner for iPhone): once after the third saved file, never in the
/// session that offered support; after Not Now it comes back once, 30 days later (`AppModel.offerFriendIfDue`).
/// It says why we ask and what the friend gets; nothing is sent unless the person picks where.
struct TellAFriendView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var shared = false

    static let message = String(localized: "1Scanner for Mac: free PDF tools, signatures and stamps, QR codes. Everything stays on your Mac.",
                                comment: "The message shared with a friend, followed by the link to the app's page.")

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Like 1Scanner? Tell a friend.")
                        .font(.app(20, weight: .bold))
                    Text("""
                        1Scanner is free: no ads, no tracking. We don't buy ads, so friends telling friends is how \
                        people find it.
                        """)
                        .font(.app(13))
                        .foregroundStyle(Theme.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Your friend gets this message:")
                    .font(.app(11.5, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                Text(verbatim: "\(Self.message) \(UpdateChecker.pageURL.absoluteString)")
                    .font(.app(13))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("You choose the app and the friend; we never see who.")
                    .font(.app(11.5))
                    .foregroundStyle(Theme.secondaryText)
            }

            HStack(spacing: 10) {
                ShareLink(item: UpdateChecker.pageURL, message: Text(Self.message)) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle())
                .simultaneousGesture(TapGesture().onEnded { answered() })
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(Self.message) \(UpdateChecker.pageURL.absoluteString)", forType: .string)
                    copied = true
                    answered()
                } label: {
                    Label(copied ? String(localized: "Copied") : String(localized: "Copy Message"),
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button(shared ? String(localized: "Done") : String(localized: "Not Now")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func answered() {
        shared = true
        model.friendShared()
    }
}
