import Foundation
import Observation

struct InstallerFile: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let size: Int64
    let modified: Date
    let source: String
    var name: String { (path as NSString).lastPathComponent }
    var ext: String { (path as NSString).pathExtension.lowercased() }
}

@Observable
final class InstallersModel {
    static let extensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]
    static let locations: [(path: String, source: String, depth: Int)] = [
        ("~/Downloads", "Downloads", 3),
        ("~/Desktop", "Desktop", 2),
        ("~/Documents", "Documents", 2),
        ("~/Library/Caches/Homebrew/downloads", "Homebrew", 1),
        ("~/Library/Caches/Homebrew/Cask", "Homebrew", 1),
        ("~/Library/Mobile Documents/com~apple~CloudDocs/Downloads", "iCloud Drive", 2),
        ("~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads", "Mail", 3),
        ("~/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/appstore/account-*/postbox/media", "Telegram", 1),
        ("~/Downloads/Telegram Desktop", "Telegram", 1),
        ("/Users/Shared", "Shared", 2),
    ]

    var files: [InstallerFile] = []
    var excluded: Set<String> = []
    var isScanning = false
    var isRemoving = false
    var lastFreed: Int64?

    var selected: [InstallerFile] { files.filter { !excluded.contains($0.path) } }
    var selectedSize: Int64 { selected.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        lastFreed = nil
        let ageDays = AppSettings.shared.installerAgeDays
        Task.detached(priority: .userInitiated) { [weak self] in
            var seen = Set<String>()
            var found: [InstallerFile] = []
            let fullDiskAccess = SystemAccess.hasFullDiskAccess
            for loc in Self.locations {
                if !fullDiskAccess && SystemAccess.isPrivacyProtected(Paths.expand(loc.path)) { continue }
                for root in Paths.glob(loc.path) where !Paths.leavesStartupDisk(root) && !AppSettings.shared.isProtected(root) {
                    Self.collect(root, depth: loc.depth, source: loc.source, seen: &seen, into: &found)
                }
            }
            for app in Paths.glob("/Applications/Install macOS*.app") where seen.insert(app).inserted {
                found.append(InstallerFile(path: app, size: 0, modified: Paths.modificationDate(app) ?? .now, source: "macOS Installer"))
            }
            let sizes = DiskWalker.measure(found.map(\.path))
            found = found.map { InstallerFile(path: $0.path, size: sizes[$0.path]?.size ?? 0, modified: $0.modified, source: $0.source) }
            let cutoff = Date().addingTimeInterval(-Double(ageDays) * 86_400)
            let recent = Set(found.filter { $0.modified > cutoff }.map(\.path))
            let sorted = found.sorted { $0.size > $1.size }
            await MainActor.run {
                self?.files = sorted
                self?.excluded = recent
                self?.isScanning = false
            }
        }
    }

    static func collect(_ dir: String, depth: Int, source: String, seen: inout Set<String>, into found: inout [InstallerFile]) {
        guard depth > 0, let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        for entry in entries where !entry.hasPrefix(".") {
            let path = dir + "/" + entry
            let ext = (entry as NSString).pathExtension.lowercased()
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { continue }
            let isInstaller = extensions.contains(ext) || (ext == "zip" && zipContainsInstaller(path))
            if isInstaller {
                // .pkg can be a bundle directory; treat both forms as one item.
                guard seen.insert(path).inserted else { continue }
                found.append(InstallerFile(path: path, size: 0, modified: Paths.modificationDate(path) ?? .now, source: source))
            } else if isDir.boolValue && !entry.hasSuffix(".app") {
                collect(path, depth: depth - 1, source: source, seen: &seen, into: &found)
            }
        }
    }

    static func zipContainsInstaller(_ path: String) -> Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64,
              size > 1_000_000, size < 4_000_000_000 else { return false }
        let r = Shell.runSync("/usr/bin/zipinfo", ["-1", path], timeout: 8)
        return r.output.split(separator: "\n").prefix(400).contains { line in
            let l = line.lowercased()
            return l.hasSuffix(".app/") || l.hasSuffix(".pkg") || l.hasSuffix(".dmg") || l.hasSuffix(".mpkg")
        }
    }

    func removeSelected() {
        let targets = selected
        guard !targets.isEmpty, !isRemoving else { return }
        isRemoving = true
        Task.detached(priority: .userInitiated) { [weak self] in
            var sizes: [String: Int64] = [:]
            for t in targets { sizes[t.path] = t.size }
            var report = Remover.remove(targets.map(\.path), mode: .trash, sizes: sizes)
            if !report.needsAdmin.isEmpty {
                let admin = await Remover.removeWithAdmin(report.needsAdmin, mode: .trash)
                report.needsAdmin = []
                report.merge(admin)
            }
            let final = report
            await MainActor.run {
                guard let self else { return }
                let removed = Set(final.removed)
                self.files.removeAll { removed.contains($0.path) }
                self.lastFreed = final.freedBytes
                self.isRemoving = false
                HistoryStore.shared.record(.installers, title: "Removed \(final.removed.count) installers",
                                           bytes: final.freedBytes, items: final.removed.count,
                                           details: final.removed.map(Paths.abbreviate))
            }
        }
    }
}
