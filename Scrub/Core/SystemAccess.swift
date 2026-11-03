import AppKit

enum SystemAccess {
    /// Full Disk Access can't be queried directly; probe a TCC-protected file instead.
    static var hasFullDiskAccess: Bool {
        let probes = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            Paths.home + "/Library/Safari/Bookmarks.plist",
            Paths.home + "/Library/Containers/com.apple.stocks",
        ]
        for probe in probes where FileManager.default.fileExists(atPath: probe) {
            let fd = open(probe, O_RDONLY)
            if fd >= 0 { close(fd); return true }
            if Paths.isDirectory(probe), (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil { return true }
        }
        return false
    }

    /// Locations macOS guards with a privacy prompt ("access data from other apps") unless the app
    /// has Full Disk Access. Scrub skips them instead of interrupting a scan with dialogs.
    static func isPrivacyProtected(_ path: String) -> Bool {
        let p = path.hasSuffix("/") ? path : path + "/"
        let home = Paths.home + "/"
        let lib = home + "Library/"
        if protectedHomeFolders.contains(where: { p.hasPrefix(home + $0) }) { return true }
        if protectedLibraryFolders.contains(where: { p.hasPrefix(lib + $0) }) { return true }
        // Media library, Photos and TV data live in caches and support folders named after their owners.
        for parent in ["Caches/", "Application Support/", "Containers/", "Group Containers/"] where p.hasPrefix(lib + parent) {
            let name = p.dropFirst((lib + parent).count).prefix { $0 != "/" }
            if protectedNamePrefixes.contains(where: { name.lowercased().hasPrefix($0) }) { return true }
        }
        return false
    }

    private static let protectedHomeFolders = [
        "Music/Music/", "Music/iTunes/", "Pictures/Photos Library.photoslibrary/", "Pictures/Photo Booth Library/",
        "Movies/TV/", "Library/Mobile Documents/",
    ]

    private static let protectedLibraryFolders = [
        "Containers/", "Group Containers/", "Mail/", "Safari/", "Messages/", "Application Support/MobileSync/",
        "Mobile Documents/", "Application Support/AddressBook/", "Application Support/CallHistoryDB/",
        "Application Support/CallHistoryTransactions/", "Biome/", "Suggestions/", "Accounts/", "Cookies/", "HomeKit/",
        "IdentityServices/", "Metadata/CoreSpotlight/", "Daemon Containers/", "Application Support/Knowledge/",
        "Application Support/FaceTime/", "Calendars/", "Reminders/", "Application Support/com.apple.TCC/",
        "Application Support/com.apple.sharedfilelist/", "Autosave Information/", "Application Support/FileProvider/",
        "CloudStorage/", "PersonalizationPortrait/", "Trial/", "DuetExpertCenter/", "Sharing/", "Photos/", "News/",
        "Stocks/", "Weather/", "Assistant/", "Intelligence/", "Shortcuts/", "Passes/", "Keychains/", "Finance/",
        "Application Support/com.apple.avfoundation/",
    ]

    private static let protectedNamePrefixes = [
        "com.apple.amp", "com.apple.itunes", "com.apple.music", "com.apple.tv", "com.apple.podcasts",
        "com.apple.photo", "com.apple.mediaanalysisd", "com.apple.medialibrary", "com.apple.iBooks", "com.apple.books",
        "com.apple.mobilesms", "com.apple.imagent", "com.apple.homed", "com.apple.findmy", "com.apple.icloud",
        "com.apple.bird", "com.apple.cloudd", "com.apple.mail", "com.apple.safari", "com.apple.siri", "com.apple.assistant",
    ].map { $0.lowercased() }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    static var runningBundleIDs: Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    static func revealInFinder(_ paths: [String]) {
        NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
    }

    static func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
