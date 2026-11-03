import Foundation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    static func expand(_ path: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        if path.hasPrefix("$HOME") { return home + path.dropFirst(5) }
        return path
    }

    static func abbreviate(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// Expands a path that may contain `*` wildcards in any component.
    static func glob(_ pattern: String) -> [String] {
        let expanded = expand(pattern)
        guard expanded.contains("*") else {
            return FileManager.default.fileExists(atPath: expanded) ? [expanded] : []
        }
        var results = [""]
        for component in expanded.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            var next: [String] = []
            for base in results {
                let dir = base.isEmpty ? "/" : base
                if component.contains("*") {
                    guard let children = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
                    for child in children where fnmatch(component, child, 0) == 0 {
                        next.append((dir == "/" ? "" : dir) + "/" + child)
                    }
                } else {
                    let candidate = (dir == "/" ? "" : dir) + "/" + component
                    if FileManager.default.fileExists(atPath: candidate) { next.append(candidate) }
                }
            }
            results = next
            if results.isEmpty { break }
        }
        return results
    }

    /// True when a path is (or is symlinked to) another volume. Cleanup never follows links off the
    /// startup disk, which would also trigger macOS's removable-volume privacy prompt.
    static func leavesStartupDisk(_ path: String) -> Bool {
        (path as NSString).resolvingSymlinksInPath.hasPrefix("/Volumes/")
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    static func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    static func children(of path: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
            .map { (path as NSString).appendingPathComponent($0) }
    }
}
