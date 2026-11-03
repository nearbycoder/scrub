import Foundation

/// Last line of defense before anything is removed. Refuses system locations,
/// top-level user folders and anything the user protected in Settings.
enum PathGuard {
    private static var hardDenied: Set<String> {
        let h = Paths.home
        return [
            "/", "/System", "/usr", "/bin", "/sbin", "/etc", "/var", "/private", "/private/var",
            "/Library", "/Applications", "/Users", "/Volumes", "/opt", "/cores",
            "/System/Volumes/Data",
            h, h + "/Desktop", h + "/Documents", h + "/Downloads", h + "/Library",
            h + "/Pictures", h + "/Movies", h + "/Music", h + "/Public", h + "/Applications",
            h + "/Library/Caches", h + "/Library/Logs", h + "/Library/Application Support",
            h + "/Library/Preferences", h + "/Library/Containers", h + "/Library/Group Containers",
            h + "/Library/Mobile Documents", h + "/.Trash", h + "/Developer", h + "/Projects",
        ]
    }

    private static let deniedPrefixes = ["/System/", "/usr/", "/bin/", "/sbin/", "/private/etc/", "/etc/"]

    enum Verdict: Equatable {
        case allowed
        case denied(String)
    }

    static func check(_ rawPath: String, protected: [String] = AppSettings.shared.protectedPaths) -> Verdict {
        let path = normalize(rawPath)
        if path.isEmpty || path.contains("/../") || path.hasSuffix("/..") { return .denied("Invalid path") }
        if hardDenied.contains(path) { return .denied("System or top-level folder") }
        if deniedPrefixes.contains(where: { path.hasPrefix($0) }) && !path.hasPrefix("/usr/local/") {
            return .denied("Inside a protected system location")
        }
        // Resolve symlinks in the parent so a link can't smuggle us into a protected tree.
        let parent = (path as NSString).deletingLastPathComponent
        let resolvedParent = (parent as NSString).resolvingSymlinksInPath
        if deniedPrefixes.contains(where: { resolvedParent.hasPrefix($0) || resolvedParent + "/" == $0 }) {
            return .denied("Resolves into a system location")
        }
        for p in protected.map({ normalize(Paths.expand($0)) }) where !p.isEmpty {
            if path == p || path.hasPrefix(p + "/") { return .denied("Protected in Settings") }
        }
        return .allowed
    }

    static func isAllowed(_ path: String) -> Bool { check(path) == .allowed }

    private static func normalize(_ path: String) -> String {
        var p = (Paths.expand(path) as NSString).standardizingPath
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
