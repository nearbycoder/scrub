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
        let lib = Paths.home + "/Library/"
        let p = path.hasSuffix("/") ? path : path + "/"
        return ["Containers/", "Group Containers/", "Mail/", "Safari/", "Messages/", "Application Support/MobileSync/",
                "Mobile Documents/", "Application Support/AddressBook/", "Application Support/CallHistoryDB/",
                "Biome/", "Suggestions/", "Accounts/", "Cookies/", "HomeKit/", "IdentityServices/", "Metadata/CoreSpotlight/",
                "Daemon Containers/", "Application Support/Knowledge/", "Application Support/FaceTime/", "Calendars/",
                "Reminders/", "Application Support/com.apple.TCC/", "Application Support/com.apple.sharedfilelist/",
                "Autosave Information/", "Application Support/FileProvider/", "CloudStorage/", "PersonalizationPortrait/",
                "Trial/", "DuetExpertCenter/", "Sharing/", "Group Containers/", "Photos/", "News/", "Stocks/", "Weather/"]
            .contains { p.hasPrefix(lib + $0) }
    }

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
