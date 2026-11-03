import SwiftUI

enum CleanGroup: String, CaseIterable, Identifiable {
    case system, browsers, developer, apps, leftovers, installers, trash, separately
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System Junk"
        case .browsers: "Browsers"
        case .developer: "Developer Tools"
        case .apps: "App Caches"
        case .leftovers: "Uninstalled App Leftovers"
        case .installers: "Old Installers"
        case .trash: "Trash"
        case .separately: "Review Separately"
        }
    }

    var subtitle: String {
        switch self {
        case .system: "Caches, logs and temporary files macOS and apps rebuild on their own."
        case .browsers: "Web caches only. History, passwords and cookies are untouched."
        case .developer: "Build products and package caches that tools can regenerate."
        case .apps: "Chat, design, media and AI app caches."
        case .leftovers: "Data left behind by apps that are no longer installed."
        case .installers: "Disk images and packages sitting in Downloads and Desktop."
        case .trash: "Files already waiting in your Trash."
        case .separately: "Large, personal items. Never selected automatically."
        }
    }

    var symbol: String {
        switch self {
        case .system: "gearshape.2.fill"
        case .browsers: "safari.fill"
        case .developer: "hammer.fill"
        case .apps: "app.badge.fill"
        case .leftovers: "questionmark.folder.fill"
        case .installers: "shippingbox.fill"
        case .trash: "trash.fill"
        case .separately: "exclamationmark.shield.fill"
        }
    }

    var tint: Color {
        switch self {
        case .system: .teal
        case .browsers: .blue
        case .developer: .indigo
        case .apps: .purple
        case .leftovers: .orange
        case .installers: .mint
        case .trash: .pink
        case .separately: .gray
        }
    }
}

struct CleanRule: Identifiable, Hashable {
    enum Scope: Hashable {
        /// Remove each child of the matched directories.
        case contents
        /// Remove the matched paths themselves.
        case items
    }

    let id: String
    let name: String
    let group: CleanGroup
    var symbol: String = "folder.fill"
    let paths: [String]
    var scope: Scope = .contents
    /// The rule is skipped while any of these apps is running.
    var bundleIDs: [String] = []
    var selectedByDefault = true
    /// Only items untouched for at least this many days are listed.
    var minAgeDays: Int? = nil
    /// Child names that must never be removed by this rule.
    var excludeNames: Set<String> = []
    var note: String? = nil
    /// Names of items inside contents-scoped directories to restrict matching to (by extension).
    var extensions: Set<String>? = nil

    static func == (l: CleanRule, r: CleanRule) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum CleanCatalog {
    static let chromiumCacheDirs = ["Cache", "Code Cache", "GPUCache", "Service Worker/CacheStorage", "Service Worker/ScriptCache", "DawnGraphiteCache", "DawnWebGPUCache", "GrShaderCache", "ShaderCache"]

    static func chromium(_ base: String) -> [String] {
        var out: [String] = []
        for dir in chromiumCacheDirs {
            out.append("\(base)/*/\(dir)")
        }
        out += ["\(base)/GrShaderCache", "\(base)/ShaderCache", "\(base)/component_crx_cache"]
        return out
    }

    static func electron(_ base: String) -> [String] {
        ["Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "Service Worker/CacheStorage", "CachedData", "logs", "Crashpad/completed"]
            .map { "\(base)/\($0)" }
    }

    /// Caches that belong to identity, sync, security or in-flight system work.
    static let protectedCacheNames: Set<String> = [
        "CloudKit", "FamilyCircle", "GameKit", "PassKit", "TemporaryItems", "INSTALLATION",
        "com.apple.HomeKit", "com.apple.homed", "com.apple.containermanagerd", "com.apple.ap.adprivacyd",
        "com.apple.Safari.SafeBrowsing", "com.apple.nsurlsessiond", "com.apple.passd", "com.apple.cache_delete",
        "com.apple.appleaccountd", "com.apple.amsaccountsd", "com.apple.bird", "com.apple.CloudDocs",
        "com.apple.akd", "com.apple.iCloudHelper", "com.apple.FeatureAccessAgent", "com.apple.findmy.findmylocateagent",
        "com.apple.frauddefensed", "com.apple.AuthenticationServicesCore.AuthenticationServicesAgent",
        "com.apple.Family-Settings.extension", "com.apple.appstoreagent", "com.apple.managedappdistributionagent",
        "com.apple.intelligenceflow.intelligenceflowd", "com.apple.icloud.searchpartyuseragent",
        "com.apple.mobileassetd", "com.apple.coreservices.useractivityd", "com.apple.CoreSimulator.SimDevice",
        "com.apple.keychainaccess", "com.apple.security", "com.apple.trustd", "com.apple.nbagent",
        "Scrub", "com.nearbycoder.scrub",
    ]

    static let rules: [CleanRule] = [
        // MARK: System junk
        CleanRule(id: "user-caches", name: "User App Caches", group: .system, symbol: "internaldrive.fill",
                  paths: ["~/Library/Caches"], excludeNames: protectedCacheNames,
                  note: "Skips caches of apps that are running and Apple account or sync data."),
        CleanRule(id: "user-logs", name: "User Logs", group: .system, symbol: "doc.text.fill",
                  paths: ["~/Library/Logs"], excludeNames: ["Scrub"]),
        CleanRule(id: "crash-reports", name: "Crash Reports", group: .system, symbol: "exclamationmark.triangle.fill",
                  paths: ["~/Library/Logs/DiagnosticReports", "/Library/Logs/DiagnosticReports"]),
        CleanRule(id: "saved-state", name: "Saved Application State", group: .system, symbol: "macwindow.on.rectangle",
                  paths: ["~/Library/Saved Application State"],
                  note: "Windows of closed apps reopen in their default layout."),
        CleanRule(id: "temp-files", name: "Temporary Files", group: .system, symbol: "clock.arrow.circlepath",
                  paths: [NSTemporaryDirectory()], minAgeDays: 3),
        CleanRule(id: "mail-downloads", name: "Mail Attachment Copies", group: .system, symbol: "envelope.fill",
                  paths: ["~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"], bundleIDs: ["com.apple.mail"]),
        CleanRule(id: "quicklook-cache", name: "Help & Spotlight", group: .system, symbol: "magnifyingglass",
                  paths: ["~/Library/Caches/com.apple.helpd", "~/Library/Caches/com.apple.parsecd",
                          "~/Library/Caches/GeoServices", "~/Library/Caches/com.apple.preferencepanes.usercache"],
                  scope: .items),
        CleanRule(id: "ios-updates", name: "iPhone & iPad Updates", group: .system, symbol: "iphone",
                  paths: ["~/Library/iTunes/iPhone Software Updates", "~/Library/iTunes/iPad Software Updates"]),

        // MARK: Browsers
        CleanRule(id: "safari", name: "Safari", group: .browsers, symbol: "safari",
                  paths: ["~/Library/Caches/com.apple.Safari", "~/Library/Containers/com.apple.Safari/Data/Library/Caches"],
                  bundleIDs: ["com.apple.Safari"], excludeNames: ["SafeBrowsing"]),
        CleanRule(id: "chrome", name: "Google Chrome", group: .browsers, symbol: "globe",
                  paths: ["~/Library/Caches/Google/Chrome"] + chromium("~/Library/Application Support/Google/Chrome"),
                  bundleIDs: ["com.google.Chrome"]),
        CleanRule(id: "chrome-canary", name: "Chrome Canary & Chromium", group: .browsers, symbol: "globe",
                  paths: ["~/Library/Caches/Google/Chrome Canary", "~/Library/Caches/Chromium"]
                    + chromium("~/Library/Application Support/Google/Chrome Canary") + chromium("~/Library/Application Support/Chromium"),
                  bundleIDs: ["com.google.Chrome.canary", "org.chromium.Chromium"]),
        CleanRule(id: "edge", name: "Microsoft Edge", group: .browsers, symbol: "globe",
                  paths: ["~/Library/Caches/Microsoft Edge", "~/Library/Caches/com.microsoft.edgemac"] + chromium("~/Library/Application Support/Microsoft Edge"),
                  bundleIDs: ["com.microsoft.edgemac"]),
        CleanRule(id: "brave", name: "Brave", group: .browsers, symbol: "shield.lefthalf.filled",
                  paths: ["~/Library/Caches/BraveSoftware"] + chromium("~/Library/Application Support/BraveSoftware/Brave-Browser"),
                  bundleIDs: ["com.brave.Browser"]),
        CleanRule(id: "arc", name: "Arc & Dia", group: .browsers, symbol: "globe",
                  paths: ["~/Library/Caches/Arc", "~/Library/Caches/company.thebrowser.Browser", "~/Library/Caches/company.thebrowser.dia"]
                    + chromium("~/Library/Application Support/Arc/User Data") + chromium("~/Library/Application Support/Dia/User Data"),
                  bundleIDs: ["company.thebrowser.Browser", "company.thebrowser.dia"]),
        CleanRule(id: "firefox", name: "Firefox", group: .browsers, symbol: "flame.fill",
                  paths: ["~/Library/Caches/Firefox/Profiles/*/cache2", "~/Library/Caches/Firefox/Profiles/*/startupCache",
                          "~/Library/Caches/Mozilla"],
                  bundleIDs: ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"]),
        CleanRule(id: "opera-vivaldi", name: "Opera & Vivaldi", group: .browsers, symbol: "globe",
                  paths: ["~/Library/Caches/com.operasoftware.Opera", "~/Library/Caches/Vivaldi"]
                    + electron("~/Library/Application Support/com.operasoftware.Opera") + chromium("~/Library/Application Support/Vivaldi"),
                  bundleIDs: ["com.operasoftware.Opera", "com.vivaldi.Vivaldi"]),

        // MARK: Developer tools
        CleanRule(id: "xcode-derived", name: "Xcode Derived Data", group: .developer, symbol: "hammer.fill",
                  paths: ["~/Library/Developer/Xcode/DerivedData"], bundleIDs: ["com.apple.dt.Xcode"],
                  note: "Projects rebuild from scratch the next time you open them."),
        CleanRule(id: "xcode-caches", name: "Xcode Caches", group: .developer, symbol: "hammer",
                  paths: ["~/Library/Caches/com.apple.dt.Xcode", "~/Library/Caches/com.apple.dt.xcodebuild",
                          "~/Library/Developer/Xcode/Products", "~/Library/Caches/org.swift.swiftpm"],
                  bundleIDs: ["com.apple.dt.Xcode"]),
        CleanRule(id: "simulator-caches", name: "Simulator Caches", group: .developer, symbol: "iphone.gen3",
                  paths: ["~/Library/Developer/CoreSimulator/Caches", "~/Library/Logs/CoreSimulator"],
                  bundleIDs: ["com.apple.iphonesimulator"]),
        CleanRule(id: "device-support", name: "Old Device Support", group: .developer, symbol: "ipad.and.iphone",
                  paths: ["~/Library/Developer/Xcode/iOS DeviceSupport", "~/Library/Developer/Xcode/watchOS DeviceSupport",
                          "~/Library/Developer/Xcode/tvOS DeviceSupport", "~/Library/Developer/Xcode/visionOS DeviceSupport"],
                  minAgeDays: 60, note: "Symbols for devices not connected in the last 60 days."),
        CleanRule(id: "xcode-archives", name: "Xcode Archives", group: .developer, symbol: "archivebox.fill",
                  paths: ["~/Library/Developer/Xcode/Archives"], selectedByDefault: false,
                  note: "Contains dSYMs needed to symbolicate crash reports for shipped builds."),
        CleanRule(id: "homebrew", name: "Homebrew Downloads", group: .developer, symbol: "mug.fill",
                  paths: ["~/Library/Caches/Homebrew"], excludeNames: ["Cask"]),
        CleanRule(id: "editors", name: "Code Editor Caches", group: .developer, symbol: "chevron.left.forwardslash.chevron.right",
                  paths: electron("~/Library/Application Support/Code") + electron("~/Library/Application Support/Cursor")
                    + electron("~/Library/Application Support/Windsurf") + ["~/Library/Caches/com.microsoft.VSCode.ShipIt",
                    "~/Library/Caches/Zed", "~/Library/Caches/dev.zed.Zed", "~/Library/Application Support/Code/CachedExtensionVSIXs"],
                  bundleIDs: ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "dev.zed.Zed"]),
        CleanRule(id: "jetbrains", name: "JetBrains IDE Caches", group: .developer, symbol: "curlybraces",
                  paths: ["~/Library/Caches/JetBrains/*/caches", "~/Library/Caches/JetBrains/*/index", "~/Library/Logs/JetBrains"],
                  scope: .items),
        CleanRule(id: "go-build", name: "Go Build Cache", group: .developer, symbol: "g.circle.fill",
                  paths: ["~/Library/Caches/go-build"]),
        CleanRule(id: "node-gyp", name: "Node Toolchain Caches", group: .developer, symbol: "n.circle.fill",
                  paths: ["~/Library/Caches/node-gyp", "~/Library/Caches/typescript", "~/.node-gyp", "~/Library/Caches/turbo"]),
        CleanRule(id: "npm", name: "npm Cache", group: .developer, symbol: "shippingbox",
                  paths: ["~/.npm/_cacache", "~/.npm/_logs", "~/.npm/_npx"], selectedByDefault: false,
                  note: "Packages download again on the next install."),
        CleanRule(id: "yarn-pnpm-bun", name: "Yarn, pnpm & Bun Caches", group: .developer, symbol: "shippingbox",
                  paths: ["~/Library/Caches/Yarn", "~/Library/pnpm/store", "~/Library/Caches/pnpm", "~/.bun/install/cache"],
                  selectedByDefault: false, note: "Packages download again on the next install."),
        CleanRule(id: "python", name: "pip & uv Caches", group: .developer, symbol: "p.circle.fill",
                  paths: ["~/Library/Caches/pip", "~/Library/Caches/pypoetry", "~/.cache/uv", "~/Library/Caches/uv", "~/.cache/pip"],
                  selectedByDefault: false, note: "Packages download again on the next install."),
        CleanRule(id: "cocoapods", name: "CocoaPods Cache", group: .developer, symbol: "leaf.fill",
                  paths: ["~/Library/Caches/CocoaPods"], selectedByDefault: false),
        CleanRule(id: "gradle", name: "Gradle & Maven Caches", group: .developer, symbol: "cup.and.saucer.fill",
                  paths: ["~/.gradle/caches", "~/.gradle/wrapper/dists"], selectedByDefault: false,
                  note: "Dependencies download again on the next build."),
        CleanRule(id: "cargo", name: "Cargo Registry Cache", group: .developer, symbol: "gearshape.fill",
                  paths: ["~/.cargo/registry/cache", "~/.cargo/registry/src", "~/.cargo/git/checkouts"], selectedByDefault: false),
        CleanRule(id: "playwright", name: "Browser Test Binaries", group: .developer, symbol: "theatermasks.fill",
                  paths: ["~/Library/Caches/ms-playwright", "~/.cache/puppeteer", "~/Library/Caches/Cypress"],
                  selectedByDefault: false, note: "Playwright, Puppeteer and Cypress browsers re-download on demand."),
        CleanRule(id: "docker-cache", name: "Docker Desktop Caches", group: .developer, symbol: "shippingbox.circle.fill",
                  paths: ["~/Library/Caches/Docker Desktop", "~/Library/Caches/com.docker.docker"],
                  bundleIDs: ["com.docker.docker"]),

        // MARK: App caches
        CleanRule(id: "slack", name: "Slack", group: .apps, symbol: "number",
                  paths: electron("~/Library/Application Support/Slack")
                    + electron("~/Library/Containers/com.tinyspeck.slackmacgap/Data/Library/Application Support/Slack"),
                  bundleIDs: ["com.tinyspeck.slackmacgap"]),
        CleanRule(id: "discord", name: "Discord", group: .apps, symbol: "bubble.left.and.bubble.right.fill",
                  paths: electron("~/Library/Application Support/discord"), bundleIDs: ["com.hnc.Discord"]),
        CleanRule(id: "teams", name: "Microsoft Teams", group: .apps, symbol: "person.3.fill",
                  paths: ["~/Library/Containers/com.microsoft.teams2/Data/Library/Caches"] + electron("~/Library/Application Support/Microsoft/Teams"),
                  bundleIDs: ["com.microsoft.teams2", "com.microsoft.teams"]),
        CleanRule(id: "zoom", name: "Zoom", group: .apps, symbol: "video.fill",
                  paths: ["~/Library/Caches/us.zoom.xos", "~/Library/Logs/zoom.us"], bundleIDs: ["us.zoom.xos"]),
        CleanRule(id: "spotify", name: "Spotify", group: .apps, symbol: "music.note",
                  paths: ["~/Library/Caches/com.spotify.client", "~/Library/Application Support/Spotify/PersistentCache"],
                  bundleIDs: ["com.spotify.client"], note: "Downloaded songs for offline use are not touched."),
        CleanRule(id: "whatsapp", name: "WhatsApp & Telegram", group: .apps, symbol: "message.fill",
                  paths: ["~/Library/Containers/net.whatsapp.WhatsApp/Data/Library/Caches", "~/Library/Caches/ru.keepcoder.Telegram"],
                  bundleIDs: ["net.whatsapp.WhatsApp", "ru.keepcoder.Telegram"]),
        CleanRule(id: "notion-figma", name: "Notion, Figma & Linear", group: .apps, symbol: "paintbrush.pointed.fill",
                  paths: electron("~/Library/Application Support/Notion") + electron("~/Library/Application Support/Figma")
                    + electron("~/Library/Application Support/Linear") + ["~/Library/Caches/com.figma.Desktop", "~/Library/Caches/notion.id"],
                  bundleIDs: ["notion.id", "com.figma.Desktop", "com.linear"]),
        CleanRule(id: "ai-apps", name: "AI App Caches", group: .apps, symbol: "brain.head.profile.fill",
                  paths: electron("~/Library/Application Support/Claude") + ["~/Library/Caches/com.openai.chat",
                    "~/Library/Caches/claude-cli-nodejs", "~/Library/Caches/com.anthropic.claudefordesktop.ShipIt",
                    "~/Library/Caches/com.openai.codex", "~/.cache/opencode"],
                  bundleIDs: ["com.anthropic.claudefordesktop", "com.openai.chat"],
                  note: "Conversations, projects and settings are kept."),
        CleanRule(id: "updaters", name: "App Updater Leftovers", group: .apps, symbol: "arrow.down.circle.fill",
                  paths: ["~/Library/Caches/*.ShipIt", "~/Library/Caches/*-updater", "~/Library/Caches/@*-updater",
                          "~/Library/Application Support/Caches/*-updater"],
                  scope: .items, note: "Downloaded update packages already installed."),

        // MARK: Leftovers & installers
        CleanRule(id: "orphans", name: "Removed App Leftovers", group: .leftovers, symbol: "questionmark.folder",
                  paths: [], scope: .items, selectedByDefault: false,
                  note: "Matched by bundle identifier and untouched for 15+ days. Review before removing."),
        CleanRule(id: "old-installers", name: "Old Installers", group: .installers, symbol: "opticaldisc.fill",
                  paths: ["~/Downloads", "~/Desktop"], selectedByDefault: false, minAgeDays: 14,
                  extensions: ["dmg", "pkg", "mpkg", "iso", "xip"]),
        CleanRule(id: "trash", name: "Trash", group: .trash, symbol: "trash.fill",
                  paths: ["~/.Trash"], note: "Emptied permanently."),

        // MARK: Review separately
        CleanRule(id: "ios-backups", name: "iPhone & iPad Backups", group: .separately, symbol: "iphone.circle.fill",
                  paths: ["~/Library/Application Support/MobileSync/Backup"], selectedByDefault: false,
                  note: "These may be your only copy of a device. Make sure you have another backup."),
        CleanRule(id: "macos-installers", name: "macOS Installer Apps", group: .separately, symbol: "applelogo",
                  paths: ["/Applications/Install macOS*.app"], scope: .items, selectedByDefault: false),
        CleanRule(id: "simulator-devices", name: "Simulator Devices", group: .separately, symbol: "iphone.gen3.radiowaves.left.and.right",
                  paths: ["~/Library/Developer/CoreSimulator/Devices/*"], scope: .items, selectedByDefault: false,
                  minAgeDays: 90, note: "Simulators not booted in 90 days, including their installed apps and data."),
        CleanRule(id: "ollama", name: "Ollama Models", group: .separately, symbol: "cube.fill",
                  paths: ["~/.ollama/models/blobs"], selectedByDefault: false,
                  note: "Local AI models. Prefer `ollama rm` for individual models."),
    ]

    static func rules(in group: CleanGroup) -> [CleanRule] { rules.filter { $0.group == group } }
}
