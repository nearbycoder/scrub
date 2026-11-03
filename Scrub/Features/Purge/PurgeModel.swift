import Foundation
import Observation

struct BuildArtifact: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let kind: String
    let size: Int64
    var name: String { (path as NSString).lastPathComponent }
}

/// The technology a project is built with, detected from its manifest files.
enum ProjectKind: String, Hashable {
    case node, rust, swift, xcode, python, gradle, flutter, php, ruby, go, cmake, other

    var label: String {
        switch self {
        case .node: "Node.js"
        case .rust: "Rust"
        case .swift: "Swift Package"
        case .xcode: "Xcode"
        case .python: "Python"
        case .gradle: "Gradle"
        case .flutter: "Flutter"
        case .php: "PHP"
        case .ruby: "Ruby"
        case .go: "Go"
        case .cmake: "C/C++"
        case .other: "Project"
        }
    }

    var badge: String {
        switch self {
        case .node: "JS"
        case .rust: "RS"
        case .swift: "SW"
        case .xcode: "XC"
        case .python: "PY"
        case .gradle: "KT"
        case .flutter: "FL"
        case .php: "PHP"
        case .ruby: "RB"
        case .go: "GO"
        case .cmake: "C++"
        case .other: "{ }"
        }
    }

    static func detect(_ dir: String, entries: Set<String>) -> ProjectKind {
        if entries.contains("Cargo.toml") { return .rust }
        if entries.contains("Package.swift") { return .swift }
        if entries.contains("pubspec.yaml") { return .flutter }
        if entries.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) || entries.contains("Podfile") { return .xcode }
        if entries.contains("package.json") { return .node }
        if ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "pom.xml"].contains(where: entries.contains) { return .gradle }
        if ["pyproject.toml", "setup.py", "requirements.txt", "Pipfile"].contains(where: entries.contains) || entries.contains(".venv") || entries.contains("venv") { return .python }
        if entries.contains("composer.json") { return .php }
        if entries.contains("Gemfile") { return .ruby }
        if entries.contains("go.mod") { return .go }
        if entries.contains("CMakeLists.txt") || entries.contains("Makefile") { return .cmake }
        return .other
    }
}

struct ProjectArtifacts: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let lastActivity: Date?
    var artifacts: [BuildArtifact]
    var kind: ProjectKind = .other
    var name: String { (path as NSString).lastPathComponent }
    var size: Int64 { artifacts.reduce(0) { $0 + $1.size } }
}

@Observable
final class PurgeModel {
    /// Artifact directory names, and the sibling files that prove they really are build output.
    static let artifactRules: [(name: String, kind: String, markers: [String]?)] = [
        ("node_modules", "Node packages", nil),
        ("target", "Rust / Maven build", ["Cargo.toml", "pom.xml", "build.sbt"]),
        (".build", "Swift build", ["Package.swift"]),
        ("build", "Build output", ["build.gradle", "build.gradle.kts", "CMakeLists.txt", "package.json", "setup.py", "pyproject.toml", "pubspec.yaml", "Makefile", "meson.build"]),
        ("dist", "Distribution build", ["package.json", "setup.py", "pyproject.toml"]),
        (".next", "Next.js build", nil),
        (".nuxt", "Nuxt build", nil),
        (".svelte-kit", "SvelteKit build", nil),
        (".turbo", "Turborepo cache", nil),
        (".parcel-cache", "Parcel cache", nil),
        (".angular", "Angular cache", nil),
        (".expo", "Expo cache", nil),
        ("DerivedData", "Xcode build", nil),
        ("Pods", "CocoaPods", ["Podfile"]),
        ("__pycache__", "Python bytecode", nil),
        (".pytest_cache", "pytest cache", nil),
        (".mypy_cache", "mypy cache", nil),
        (".ruff_cache", "Ruff cache", nil),
        (".venv", "Python virtualenv", nil),
        ("venv", "Python virtualenv", nil),
        (".gradle", "Gradle cache", ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]),
        (".dart_tool", "Dart tooling", ["pubspec.yaml"]),
        ("coverage", "Test coverage", ["package.json"]),
        ("vendor", "Vendored packages", ["composer.json", "Gemfile"]),
    ]
    static let maxDepth = 6

    var projects: [ProjectArtifacts] = []
    var excluded: Set<String> = []
    var isScanning = false
    var isPurging = false
    var scannedDirs = 0
    var lastFreed: Int64?

    var selectedArtifacts: [BuildArtifact] {
        projects.flatMap(\.artifacts).filter { !excluded.contains($0.path) }
    }
    var selectedSize: Int64 { selectedArtifacts.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { projects.reduce(0) { $0 + $1.size } }

    var existingRoots: [String] {
        AppSettings.shared.projectRoots.map(Paths.expand).filter(Paths.isDirectory)
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        projects = []
        excluded = []
        lastFreed = nil
        let roots = existingRoots
        let recentDays = AppSettings.shared.purgeRecentDays
        Task.detached(priority: .userInitiated) { [weak self] in
            var found: [String: [BuildArtifact]] = [:]
            var visited = 0
            for root in roots {
                Self.walk(root, depth: 0) { dir, artifactKind in
                    visited += 1
                    if visited % 200 == 0 { let v = visited; Task { @MainActor in self?.scannedDirs = v } }
                    guard let kind = artifactKind else { return }
                    let project = (dir as NSString).deletingLastPathComponent
                    found[project, default: []].append(BuildArtifact(path: dir, kind: kind, size: 0))
                }
            }
            // Skip anything git tracks, then measure every artifact in one parallel walk.
            let flat = found.flatMap { project, list in list.map { (project, $0) } }
                .filter { !Self.isTrackedByGit($0.1.path, project: $0.0) }
            let measured = DiskWalker.measure(flat.map(\.1.path))
            var sized: [String: [BuildArtifact]] = [:]
            for (project, artifact) in flat {
                guard let size = measured[artifact.path]?.size, size > 0 else { continue }
                sized[project, default: []].append(BuildArtifact(path: artifact.path, kind: artifact.kind, size: size))
            }
            let cutoff = Date().addingTimeInterval(-Double(recentDays) * 86_400)
            var result: [ProjectArtifacts] = []
            var recent: Set<String> = []
            for (project, artifacts) in sized {
                let activity = Self.lastActivity(project, ignoring: Set(artifacts.map(\.name)))
                if activity.map({ $0 > cutoff }) ?? true { recent.formUnion(artifacts.map(\.path)) }
                let entries = Set((try? FileManager.default.contentsOfDirectory(atPath: project)) ?? [])
                result.append(ProjectArtifacts(path: project, lastActivity: activity, artifacts: artifacts.sorted { $0.size > $1.size },
                                               kind: ProjectKind.detect(project, entries: entries)))
            }
            let sorted = result.sorted { $0.size > $1.size }
            await MainActor.run {
                guard let self else { return }
                self.projects = sorted
                self.excluded = recent
                self.isScanning = false
            }
        }
    }

    static func walk(_ dir: String, depth: Int, visit: (String, String?) -> Void) {
        guard depth <= maxDepth, let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        let entrySet = Set(entries)
        for entry in entries {
            let path = dir + "/" + entry
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil { continue }
            if let rule = artifactRules.first(where: { $0.name == entry }) {
                let qualifies: Bool
                if let markers = rule.markers {
                    qualifies = markers.contains(where: entrySet.contains)
                } else if entry == "venv" || entry == ".venv" {
                    qualifies = FileManager.default.fileExists(atPath: path + "/pyvenv.cfg")
                } else {
                    qualifies = true
                }
                if qualifies {
                    visit(path, rule.kind)
                    continue
                }
            }
            if entry.hasPrefix(".") || entry.hasSuffix(".app") || entry.hasSuffix(".xcodeproj") || entry == "Library" { continue }
            visit(path, nil)
            walk(path, depth: depth + 1, visit: visit)
        }
    }

    static func lastActivity(_ project: String, ignoring: Set<String>) -> Date? {
        var latest: Date?
        for entry in (try? FileManager.default.contentsOfDirectory(atPath: project)) ?? [] where !ignoring.contains(entry) {
            if let d = Paths.modificationDate(project + "/" + entry), d > (latest ?? .distantPast) { latest = d }
        }
        if let gitHead = Paths.modificationDate(project + "/.git/index"), gitHead > (latest ?? .distantPast) { latest = gitHead }
        return latest
    }

    /// Never purge directories whose contents are committed to git.
    static func isTrackedByGit(_ path: String, project: String) -> Bool {
        guard ["build", "dist", "vendor", "target", "coverage", "Pods"].contains((path as NSString).lastPathComponent) else { return false }
        var dir = project
        var hasGit = false
        while dir != "/" && !dir.isEmpty {
            if FileManager.default.fileExists(atPath: dir + "/.git") { hasGit = true; break }
            dir = (dir as NSString).deletingLastPathComponent
        }
        guard hasGit else { return false }
        let r = Shell.runSync("/usr/bin/git", ["-C", project, "ls-files", "--", (path as NSString).lastPathComponent], timeout: 10)
        return !r.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func purge() {
        let targets = selectedArtifacts
        guard !targets.isEmpty, !isPurging else { return }
        isPurging = true
        let mode = AppSettings.shared.purgeRemovalMode
        Task.detached(priority: .userInitiated) { [weak self] in
            var sizes: [String: Int64] = [:]
            for t in targets { sizes[t.path] = t.size }
            let report = Remover.remove(targets.map(\.path), mode: mode, sizes: sizes)
            await MainActor.run {
                guard let self else { return }
                let removed = Set(report.removed)
                self.projects = self.projects.compactMap { p in
                    var p = p
                    p.artifacts.removeAll { removed.contains($0.path) }
                    return p.artifacts.isEmpty ? nil : p
                }
                self.lastFreed = report.freedBytes
                self.isPurging = false
                HistoryStore.shared.record(.purge, title: "Purged \(report.removed.count) build folders",
                                           bytes: report.freedBytes, items: report.removed.count,
                                           details: report.removed.map(Paths.abbreviate))
            }
        }
    }
}
