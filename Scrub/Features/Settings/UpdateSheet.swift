import SwiftUI

struct UpdateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let updater = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(subtitle).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(22)
        .frame(width: 500)
    }

    private var title: String {
        switch updater.phase {
        case .available(let r): "Scrub \(r.version) is available"
        case .downloading, .installing: "Updating Scrub"
        case .upToDate: "Scrub is up to date"
        case .failed: "Update failed"
        default: "Checking for updates…"
        }
    }

    private var subtitle: String {
        switch updater.phase {
        case .available: "You have version \(Updater.currentVersion)."
        case .upToDate: "Version \(Updater.currentVersion) is the newest version available."
        case .downloading: "Downloading…"
        case .installing: "Verifying the signature and installing…"
        case .failed(let message): message
        default: "Contacting GitHub."
        }
    }

    @ViewBuilder private var content: some View {
        switch updater.phase {
        case .available(let release):
            ScrollView {
                Text((try? AttributedString(markdown: release.notes, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(release.notes))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(height: 220)
            .background(.background.secondary, in: .rect(cornerRadius: 8))
            HStack {
                Button("Skip This Version") { updater.skip(release) }
                Spacer()
                Button("Later") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Install and Relaunch") { Task { await updater.install(release) } }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        case .downloading(let fraction):
            ProgressView(value: fraction)
        case .installing, .checking:
            ProgressView().frame(maxWidth: .infinity)
        default:
            HStack {
                Spacer()
                Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}
