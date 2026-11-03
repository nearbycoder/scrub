import AppKit

struct InstalledApp: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let bundleID: String
    let version: String
    let executable: String?
    let isAppStore: Bool
    let lastUsed: Date?

    var url: URL { URL(fileURLWithPath: path) }
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    var location: String { Paths.abbreviate((path as NSString).deletingLastPathComponent) }
}

enum AppInventory {
    static let searchRoots = ["/Applications", "~/Applications", "/Applications/Utilities", "/Applications/Setapp"]

    /// Apple components that are hidden from the uninstaller even if they live in /Applications.
    static let essentialBundleIDs: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systempreferences",
        "com.apple.Safari", "com.apple.AppStore", "com.apple.Terminal", "com.apple.ActivityMonitor",
        "com.apple.SystemProfiler", "com.apple.DiskUtility", "com.apple.Console", "com.apple.KeychainAccess",
        "com.apple.Passwords", "com.apple.backup.launcher", "com.apple.MigrateAssistant", "com.apple.BootCampAssistant",
        "com.apple.ScriptEditor2", "com.apple.VoiceOverUtility", "com.apple.bluetoothfileexchange",
        "com.apple.ColorSyncUtility", "com.apple.audio.AudioMIDISetup", "com.apple.grapher", "com.apple.screenshot.launcher",
        "com.nearbycoder.scrub",
    ]

    static func appBundles() -> [String] {
        var paths: [String] = []
        var seen = Set<String>()
        for root in searchRoots.map(Paths.expand) {
            for child in Paths.children(of: root) {
                if child.hasSuffix(".app") {
                    if seen.insert(child).inserted { paths.append(child) }
                } else if Paths.isDirectory(child), !child.hasSuffix("Utilities") {
                    // One level of vendor folders, e.g. /Applications/Adobe Photoshop 2025/
                    for nested in Paths.children(of: child) where nested.hasSuffix(".app") {
                        if seen.insert(nested).inserted { paths.append(nested) }
                    }
                }
            }
        }
        return paths
    }

    static func load() -> [InstalledApp] {
        appBundles().compactMap(makeApp).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func makeApp(_ path: String) -> InstalledApp? {
        guard let bundle = Bundle(path: path), let id = bundle.bundleIdentifier else { return nil }
        if essentialBundleIDs.contains(id) { return nil }
        let isAppStore = FileManager.default.fileExists(atPath: path + "/Contents/_MASReceipt/receipt")
        // Apple's own apps are part of the system unless they came from the App Store (Pages, Keynote…).
        if id.hasPrefix("com.apple.") && !isAppStore { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        let version = info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String ?? ""
        return InstalledApp(path: path, name: name, bundleID: id, version: version,
                            executable: info["CFBundleExecutable"] as? String,
                            isAppStore: isAppStore, lastUsed: lastUsedDate(path))
    }

    static func lastUsedDate(_ path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Every bundle identifier we can find, including system apps, used to recognise orphaned data.
    static func installedBundleIDs() -> Set<String> {
        var ids = Set<String>()
        let roots = searchRoots + ["/System/Applications", "/System/Applications/Utilities", "/System/Library/CoreServices",
                                   "/Library/PreferencePanes", "~/Library/PreferencePanes"]
        for root in roots.map(Paths.expand) {
            for child in Paths.children(of: root) {
                if let id = Bundle(path: child)?.bundleIdentifier { ids.insert(id) }
                if Paths.isDirectory(child), !child.hasSuffix(".app") {
                    for nested in Paths.children(of: child) {
                        if let id = Bundle(path: nested)?.bundleIdentifier { ids.insert(id) }
                    }
                }
            }
        }
        ids.formUnion(SystemAccess.runningBundleIDs)
        // Login items and helpers registered with launchd.
        for dir in ["~/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"] {
            for plist in Paths.children(of: Paths.expand(dir)) where plist.hasSuffix(".plist") {
                ids.insert(((plist as NSString).lastPathComponent as NSString).deletingPathExtension)
            }
        }
        return ids
    }
}

struct Leftover: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let kind: String
    let size: Int64
    let requiresAdmin: Bool
    let selectedByDefault: Bool
}

enum LeftoverFinder {
    static func find(for app: InstalledApp) -> [Leftover] {
        let id = app.bundleID
        let idLower = id.lowercased()
        let vendorProduct = OrphanFinder.vendorProduct(id)
        var names = Set<String>()
        for n in [app.name, app.executable, (app.path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")] {
            if let n, n.count >= 3 { names.insert(n.lowercased()) }
        }

        func matchesExact(_ entry: String) -> Bool {
            let e = entry.lowercased()
            return e == idLower || names.contains(e)
        }
        func matchesPrefix(_ entry: String) -> Bool {
            let e = entry.lowercased()
            return e == idLower || e.hasPrefix(idLower + ".")
        }
        func matchesPlist(_ entry: String) -> Bool {
            let e = entry.lowercased()
            guard e.hasSuffix(".plist") else { return false }
            let base = String(e.dropLast(6))
            return base == idLower || base.hasPrefix(idLower + ".")
        }
        func matchesLaunchd(_ entry: String) -> Bool {
            let e = entry.lowercased()
            guard e.hasSuffix(".plist") else { return false }
            return e.hasPrefix(idLower) || (vendorProduct.split(separator: ".").count == 3 && e.hasPrefix(vendorProduct + "."))
        }

        typealias Rule = (dir: String, kind: String, match: (String) -> Bool, selected: Bool)
        let rules: [Rule] = [
            ("~/Library/Application Support", "Application Support", matchesExact, true),
            ("~/Library/Caches", "Caches", { matchesExact($0) || matchesPrefix($0) }, true),
            ("~/Library/Containers", "Container", matchesPrefix, true),
            ("~/Library/Group Containers", "Shared Group Container", { $0.lowercased().hasSuffix("." + idLower) || $0.lowercased() == "group." + idLower }, false),
            ("~/Library/Preferences", "Preferences", matchesPlist, true),
            ("~/Library/Preferences/ByHost", "Preferences", { $0.lowercased().hasPrefix(idLower + ".") }, true),
            ("~/Library/Saved Application State", "Saved State", { $0.lowercased() == idLower + ".savedstate" }, true),
            ("~/Library/Logs", "Logs", matchesExact, true),
            ("~/Library/HTTPStorages", "HTTP Storage", { matchesPrefix($0) || $0.lowercased() == idLower + ".binarycookies" }, true),
            ("~/Library/WebKit", "WebKit Data", matchesPrefix, true),
            ("~/Library/Cookies", "Cookies", { $0.lowercased() == idLower + ".binarycookies" }, true),
            ("~/Library/Application Scripts", "Application Scripts", matchesPrefix, true),
            ("~/Library/LaunchAgents", "Launch Agent", matchesLaunchd, true),
            ("~/Library/Autosave Information", "Autosave", { $0.lowercased().hasPrefix(idLower) }, true),
            ("/Library/Application Support", "System Application Support", matchesExact, true),
            ("/Library/Caches", "System Caches", matchesPrefix, true),
            ("/Library/Preferences", "System Preferences", matchesPlist, true),
            ("/Library/LaunchAgents", "System Launch Agent", matchesLaunchd, true),
            ("/Library/LaunchDaemons", "Launch Daemon", matchesLaunchd, true),
            ("/Library/PrivilegedHelperTools", "Privileged Helper", { $0.lowercased().hasPrefix(idLower) || $0.lowercased().hasPrefix(vendorProduct) }, true),
            ("/Library/Logs", "System Logs", matchesExact, true),
            ("/Users/Shared", "Shared Files", matchesExact, false),
        ]

        var found: [Leftover] = []
        var seen = Set<String>()
        let fullDiskAccess = SystemAccess.hasFullDiskAccess
        for rule in rules {
            let dir = Paths.expand(rule.dir)
            for entry in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where rule.match(entry) {
                let path = dir + "/" + entry
                guard seen.insert(path).inserted, PathGuard.isAllowed(path) else { continue }
                let parentWritable = FileManager.default.isWritableFile(atPath: dir)
                // Measuring another app's container without Full Disk Access would trigger a privacy prompt.
                let measurable = fullDiskAccess || !SystemAccess.isPrivacyProtected(path)
                found.append(Leftover(path: path, kind: rule.kind, size: measurable ? FileSizer.allocatedSize(atPath: path) : 0,
                                      requiresAdmin: !parentWritable,
                                      selectedByDefault: rule.selected))
            }
        }
        return found.sorted { $0.size > $1.size }
    }
}
