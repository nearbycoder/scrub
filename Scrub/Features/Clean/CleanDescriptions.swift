import SwiftUI

/// How confident Scrub is that removing a category has no downside.
enum CleanSafety {
    case safe, redownload, review, permanent

    var title: String {
        switch self {
        case .safe: "Safe to remove"
        case .redownload: "Downloads again when needed"
        case .review: "Review before removing"
        case .permanent: "Removed permanently"
        }
    }

    var symbol: String {
        switch self {
        case .safe: "checkmark.shield.fill"
        case .redownload: "arrow.down.circle.fill"
        case .review: "exclamationmark.triangle.fill"
        case .permanent: "trash.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .safe: .green
        case .redownload: .blue
        case .review: .orange
        case .permanent: .pink
        }
    }
}

extension CleanRule {
    var safety: CleanSafety {
        switch id {
        case "trash": return .permanent
        case "xcode-archives", "orphans", "old-installers": return .review
        default: break
        }
        if group == .separately { return .review }
        return selectedByDefault ? .safe : .redownload
    }

    /// One or two sentences explaining what the category is and what happens after cleaning it.
    var about: String {
        Self.descriptions[id] ?? note ?? group.subtitle
    }

    /// An app whose icon represents this category, when there is one.
    var iconBundleID: String? {
        Self.iconApps[id] ?? bundleIDs.first
    }

    private static let iconApps: [String: String] = [
        "user-logs": "com.apple.Console",
        "crash-reports": "com.apple.Console",
        "mail-downloads": "com.apple.mail",
        "quicklook-cache": "com.apple.systempreferences",
        "ios-updates": "com.apple.finder",
        "xcode-archives": "com.apple.dt.Xcode",
        "device-support": "com.apple.dt.Xcode",
        "simulator-devices": "com.apple.iphonesimulator",
        "ios-backups": "com.apple.finder",
        "macos-installers": "com.apple.AppStore",
        "jetbrains": "com.jetbrains.intellij",
        "ollama": "com.electron.ollama",
    ]

    private static let descriptions: [String: String] = [
        "user-caches": "Data apps store to load faster, like thumbnails, downloaded artwork and compiled scripts. Apps rebuild it as they need it, so the first launch after cleaning can be slightly slower.",
        "user-logs": "Diagnostic text files apps write while they run. They're only useful when troubleshooting a problem.",
        "crash-reports": "Reports macOS saves when an app crashes or hangs. They've already been offered to Apple and developers.",
        "saved-state": "The window positions macOS uses to reopen apps where you left off. Closed apps will open with their default windows next time.",
        "temp-files": "Temporary files more than three days old that apps forgot to delete.",
        "mail-downloads": "Copies of attachments you opened in Mail. The originals stay in your messages.",
        "quicklook-cache": "Caches for Help, Spotlight suggestions and Maps tiles. macOS rebuilds them automatically.",
        "ios-updates": "Software updates downloaded by Finder for iPhone and iPad. Finder downloads them again when needed.",
        "safari": "Web page images, scripts and styles Safari keeps to load sites faster. Your history, passwords, bookmarks and open tabs aren't affected.",
        "chrome": "Chrome's page cache, code cache and GPU shader cache for every profile. Bookmarks, passwords, history and extensions aren't affected.",
        "chrome-canary": "Page and code caches for Chrome Canary and Chromium.",
        "edge": "Microsoft Edge's page, code and GPU caches for every profile.",
        "brave": "Brave's page, code and GPU caches for every profile.",
        "arc": "Page, code and GPU caches for Arc and Dia across every profile.",
        "firefox": "Firefox's disk cache and startup cache for every profile.",
        "opera-vivaldi": "Page and code caches for Opera and Vivaldi.",
        "xcode-derived": "Intermediate build products and indexes. Xcode rebuilds them the next time you open each project, which takes a little longer once.",
        "xcode-caches": "Xcode's module caches, Swift Package Manager checkouts and old build products.",
        "simulator-caches": "Caches and logs created by the iOS, watchOS and visionOS simulators.",
        "device-support": "Debug symbols Xcode copies from devices you connect. Only symbols for devices you haven't connected in 60 days are listed.",
        "xcode-archives": "Archived builds you made for distribution. They hold the debug symbols needed to read crash reports from those versions.",
        "homebrew": "Bottles and source archives Homebrew downloaded while installing packages.",
        "editors": "Caches, logs and downloaded extension packages for VS Code, Cursor, Windsurf and Zed. Settings and extensions stay installed.",
        "jetbrains": "Indexes, caches and logs for JetBrains IDEs. Projects reindex the next time you open them.",
        "go-build": "Go's compiled package cache. Builds repopulate it automatically.",
        "node-gyp": "Headers and caches for building native Node.js modules and TypeScript and Turborepo caches.",
        "npm": "Every package npm has ever downloaded. Installs fetch packages from the registry again as needed.",
        "yarn-pnpm-bun": "Package caches for Yarn, pnpm and Bun. Installs fetch packages again as needed.",
        "python": "Wheels and packages downloaded by pip, Poetry and uv.",
        "cocoapods": "Downloaded pod sources. `pod install` fetches them again.",
        "gradle": "Gradle's dependency cache and downloaded Gradle distributions.",
        "cargo": "Crates downloaded by Cargo. Builds fetch them again when needed.",
        "playwright": "Browser binaries downloaded by Playwright, Puppeteer and Cypress for testing.",
        "docker-cache": "Docker Desktop's app caches. Images, containers and volumes aren't touched.",
        "slack": "Slack's page and code caches. Messages and files stay in your workspace.",
        "discord": "Discord's media, page and code caches.",
        "teams": "Microsoft Teams caches.",
        "zoom": "Zoom's caches and logs. Recordings aren't affected.",
        "spotify": "Spotify's streaming cache. Songs you downloaded for offline listening aren't touched.",
        "whatsapp": "Media caches for WhatsApp and Telegram. Your chats aren't affected.",
        "notion-figma": "Page and code caches for Notion, Figma and Linear. Your documents live in the cloud and aren't affected.",
        "ai-apps": "Caches and downloaded updates for Claude, ChatGPT and AI command-line tools. Conversations, projects and settings are kept.",
        "updaters": "Update packages apps downloaded and already installed.",
        "orphans": "Settings, caches and data from apps that are no longer on your Mac and haven't been used for at least 15 days. They're moved to the Trash, so you can put anything back.",
        "old-installers": "Disk images and installer packages in Downloads and on your Desktop that are more than two weeks old. They're moved to the Trash.",
        "trash": "Everything currently in your Trash. It's deleted permanently.",
        "ios-backups": "Local backups of your iPhone and iPad. If iCloud Backup is off, these may be your only copies.",
        "macos-installers": "Full macOS installer apps. Download them again from the App Store when you need them.",
        "simulator-devices": "Simulators you haven't booted in 90 days, including the apps and data installed on them.",
        "ollama": "Local AI model files downloaded by Ollama.",
    ]
}

/// The icon for a cleanup category: the owning app's icon when there is one, otherwise a
/// System Settings-style tile.
struct RuleIcon: View {
    let rule: CleanRule
    var size: CGFloat = 28

    var body: some View {
        if let image = Self.appIcon(rule.iconBundleID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else if rule.id == "trash" {
            Image(nsImage: NSImage(named: NSImage.trashFullName) ?? NSImage())
                .resizable()
                .frame(width: size, height: size)
        } else {
            SymbolTile(symbol: rule.symbol, color: rule.group.color, size: size)
        }
    }

    private static var cache: [String: NSImage?] = [:]

    static func appIcon(_ bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let hit = cache[bundleID] { return hit }
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            NSWorkspace.shared.icon(forFile: $0.path)
        }
        cache[bundleID] = image
        return image
    }
}

/// A rounded-square tile with a white symbol, as used for settings panes across macOS.
struct SymbolTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(color.gradient)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
    }
}
