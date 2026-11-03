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
                ReleaseNotes(markdown: release.notes)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
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

/// Renders GitHub release notes: headings, bullets and inline formatting. Code blocks and bare links are left out.
private struct ReleaseNotes: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                switch line {
                case .heading(let text):
                    Text(inline(text)).font(.headline).padding(.top, 6)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        Text(inline(text))
                    }
                case .paragraph(let text):
                    Text(inline(text))
                }
            }
        }
    }

    private enum Line { case heading(String), bullet(String), paragraph(String) }

    private var lines: [Line] {
        var result: [Line] = []
        var inCode = false
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { inCode.toggle(); continue }
            if inCode || line.isEmpty || line.hasPrefix("http") { continue }
            if line.hasPrefix("#") {
                result.append(.heading(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                result.append(.bullet(String(line.dropFirst(2))))
            } else {
                result.append(.paragraph(line))
            }
        }
        return result
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}
