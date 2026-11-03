import SwiftUI
import Observation

struct OptimizeTask: Identifiable, Hashable {
    enum Kind: Hashable {
        /// Runs as the current user.
        case user([String])
        /// Collected into one administrator prompt.
        case admin(String)
        /// Implemented in Swift.
        case native
    }

    let id: String
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let kind: Kind
    var selectedByDefault = true
    /// Bundle IDs that must not be running for this task to be safe.
    var skipWhileRunning: [String] = []
    var requiresTool: String? = nil

    var requiresAdmin: Bool { if case .admin = kind { return true }; return false }
}

enum OptimizeStatus: Equatable {
    case pending, running, done(String), skipped(String), failed(String)
}

@Observable
final class OptimizeModel {
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    static let browsers = ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser"]

    let tasks: [OptimizeTask] = [
        OptimizeTask(id: "quicklook", title: "Rebuild Quick Look Cache", detail: "Fixes missing or stale thumbnails and previews in Finder.",
                     symbol: "eye.fill", tint: .blue, kind: .user(["/usr/bin/qlmanage -r cache", "/usr/bin/qlmanage -r"])),
        OptimizeTask(id: "launchservices", title: "Rebuild Launch Services", detail: "Removes duplicate entries from “Open With” menus and fixes wrong default apps.",
                     symbol: "arrow.up.forward.app.fill", tint: .indigo,
                     kind: .user(["\(lsregister) -r -domain local -domain system -domain user"])),
        OptimizeTask(id: "broken-agents", title: "Remove Broken Launch Agents", detail: "Moves login agents whose program no longer exists to the Trash.",
                     symbol: "bolt.slash.fill", tint: .orange, kind: .native),
        OptimizeTask(id: "corrupt-prefs", title: "Repair Preference Files", detail: "Finds damaged .plist files that make apps forget settings or crash.",
                     symbol: "wrench.and.screwdriver.fill", tint: .teal, kind: .native),
        OptimizeTask(id: "quarantine", title: "Clear Download History Log", detail: "Wipes the Gatekeeper record of every file you ever downloaded.",
                     symbol: "hand.raised.fill", tint: .pink,
                     kind: .user(["/usr/bin/sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 'DELETE FROM LSQuarantineEvent; VACUUM;'"])),
        OptimizeTask(id: "fonts", title: "Reset Font Caches", detail: "Fixes garbled text and font rendering glitches.",
                     symbol: "textformat", tint: .purple,
                     kind: .user(["/usr/bin/atsutil databases -removeUser", "/usr/bin/atsutil server -shutdown", "/usr/bin/atsutil server -ping"]),
                     skipWhileRunning: browsers),
        OptimizeTask(id: "mail-vacuum", title: "Speed Up Mail", detail: "Compacts Mail's message index so search and scrolling stay fast.",
                     symbol: "envelope.badge.fill", tint: .cyan, kind: .native, skipWhileRunning: ["com.apple.mail"]),
        OptimizeTask(id: "simulators", title: "Delete Unavailable Simulators", detail: "Removes simulators for SDKs that are no longer installed.",
                     symbol: "iphone.slash", tint: .gray, kind: .user(["/usr/bin/xcrun simctl delete unavailable"]),
                     requiresTool: "/Applications/Xcode.app"),
        OptimizeTask(id: "brew", title: "Homebrew Cleanup", detail: "Removes outdated formula versions and stale downloads.",
                     symbol: "mug.fill", tint: .brown, kind: .user(["brew cleanup --prune=all -s"]),
                     selectedByDefault: false, requiresTool: "brew"),
        OptimizeTask(id: "dns", title: "Flush DNS Cache", detail: "Fixes websites that won't load after network or DNS changes.",
                     symbol: "network", tint: .green, kind: .admin("/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder")),
        OptimizeTask(id: "memory", title: "Free Up Memory", detail: "Releases inactive memory held by closed apps.",
                     symbol: "memorychip.fill", tint: .mint, kind: .admin("/usr/sbin/purge")),
        OptimizeTask(id: "snapshots", title: "Thin Time Machine Snapshots", detail: "Reclaims space held by local snapshots. Your backup disk is untouched.",
                     symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90", tint: .yellow,
                     kind: .admin("/usr/bin/tmutil thinlocalsnapshots / 999999999999 4")),
        OptimizeTask(id: "icons", title: "Rebuild Icon Cache", detail: "Fixes blank, generic or outdated app icons in Finder and the Dock.",
                     symbol: "app.dashed", tint: .blue,
                     kind: .admin("/bin/rm -rf /Library/Caches/com.apple.iconservices.store; /usr/bin/find /private/var/folders -name com.apple.dock.iconcache -delete 2>/dev/null; /usr/bin/find /private/var/folders -name com.apple.iconservices -type d -prune -exec /bin/rm -rf {} + 2>/dev/null; /usr/bin/killall Dock"),
                     selectedByDefault: false),
        OptimizeTask(id: "permissions", title: "Repair Home Folder Permissions", detail: "Resets ownership in your home folder. Can take a few minutes.",
                     symbol: "lock.shield.fill", tint: .red,
                     kind: .admin("/usr/sbin/diskutil resetUserPermissions / \(getuid())"), selectedByDefault: false),
        OptimizeTask(id: "spotlight", title: "Reindex Spotlight", detail: "Rebuilds the search index when results are missing. Indexing runs for a while afterwards.",
                     symbol: "magnifyingglass.circle.fill", tint: .orange,
                     kind: .admin("/usr/bin/mdutil -E /"), selectedByDefault: false),
        OptimizeTask(id: "refresh-ui", title: "Restart Finder & Dock", detail: "Clears hangs in the Dock, Finder, menu bar and Notification Center.",
                     symbol: "dock.rectangle", tint: .teal,
                     kind: .user(["/usr/bin/killall Dock", "/usr/bin/killall Finder", "/usr/bin/killall SystemUIServer", "/usr/bin/killall NotificationCenter"]),
                     selectedByDefault: false),
    ]

    var selected: Set<String>
    var status: [String: OptimizeStatus] = [:]
    var isRunning = false
    var finishedAt: Date?
    var touchIDEnabled = false
    var touchIDBusy = false

    init() {
        selected = Set(tasks.filter(\.selectedByDefault).map(\.id))
        refreshTouchID()
    }

    var availableTasks: [OptimizeTask] { tasks.filter(isAvailable) }

    func isAvailable(_ task: OptimizeTask) -> Bool {
        guard let tool = task.requiresTool else { return true }
        if tool.hasPrefix("/") { return FileManager.default.fileExists(atPath: tool) }
        return ["/opt/homebrew/bin/", "/usr/local/bin/"].contains { FileManager.default.isExecutableFile(atPath: $0 + tool) }
    }

    /// Runs the selected tasks, or just `only` when given (used by the menu bar's Free RAM).
    func run(only: Set<String>? = nil) {
        guard !isRunning else { return }
        let ids = only ?? selected
        let chosen = availableTasks.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return }
        isRunning = true
        finishedAt = nil
        status = Dictionary(uniqueKeysWithValues: chosen.map { ($0.id, OptimizeStatus.pending) })
        let running = SystemAccess.runningBundleIDs

        Task { @MainActor in
            var adminBatch: [OptimizeTask] = []
            for task in chosen {
                if let blocker = task.skipWhileRunning.first(where: running.contains) {
                    let name = NSRunningApplication.runningApplications(withBundleIdentifier: blocker).first?.localizedName ?? blocker
                    status[task.id] = .skipped("\(name) is open")
                    continue
                }
                switch task.kind {
                case .admin:
                    adminBatch.append(task)
                case .user(let commands):
                    status[task.id] = .running
                    var failure: String?
                    for command in commands {
                        let r = await Shell.run("/bin/zsh", ["-c", command.replacingOccurrences(of: "~/", with: Paths.home + "/")])
                        if !r.success && task.id != "refresh-ui" && task.id != "fonts" {
                            failure = r.error ?? "Exit code \(r.status)"
                        }
                    }
                    status[task.id] = failure.map { .failed(String($0.prefix(120))) } ?? .done("Done")
                case .native:
                    status[task.id] = .running
                    status[task.id] = await runNative(task)
                }
            }
            if !adminBatch.isEmpty {
                adminBatch.forEach { status[$0.id] = .running }
                let script = adminBatch.map { t -> String in
                    guard case .admin(let cmd) = t.kind else { return "" }
                    return "( \(cmd) ) >/dev/null 2>&1 && echo 'OK:\(t.id)' || echo 'FAIL:\(t.id)'"
                }.joined(separator: "; ")
                let result = await Shell.runAsAdmin(script)
                for t in adminBatch {
                    if result.output.contains("OK:\(t.id)") {
                        status[t.id] = .done("Done")
                    } else if result.output.contains("FAIL:\(t.id)") {
                        status[t.id] = t.id == "snapshots" ? .done("No snapshots to thin") : .failed("Command reported an error")
                    } else {
                        status[t.id] = .skipped(result.error == "Cancelled" ? "Admin approval cancelled" : (result.error ?? "Not run"))
                    }
                }
            }
            isRunning = false
            finishedAt = .now
            let doneCount = status.values.filter { if case .done = $0 { return true }; return false }.count
            HistoryStore.shared.record(.optimize, title: "Ran \(doneCount.counted("maintenance task"))", bytes: 0, items: doneCount,
                                       details: chosen.filter { if case .done = status[$0.id] { return true }; return false }.map(\.title))
        }
    }

    private func runNative(_ task: OptimizeTask) async -> OptimizeStatus {
        switch task.id {
        case "broken-agents":
            let broken = await Task.detached { Self.brokenLaunchAgents() }.value
            guard !broken.isEmpty else { return .done("All agents healthy") }
            for plist in broken {
                _ = await Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())", plist])
            }
            let report = Remover.remove(broken, mode: .trash)
            return .done("Removed \(report.removed.count)")
        case "corrupt-prefs":
            let corrupt = await Task.detached { Self.corruptPreferences() }.value
            guard !corrupt.isEmpty else { return .done("No damaged files") }
            let report = Remover.remove(corrupt, mode: .trash)
            return .done("Repaired \(report.removed.count)")
        case "mail-vacuum":
            let indexes = Paths.glob("~/Library/Mail/V*/MailData/Envelope Index")
            guard !indexes.isEmpty else { return .skipped(SystemAccess.hasFullDiskAccess ? "Mail not set up" : "Needs Full Disk Access") }
            for index in indexes {
                let r = await Shell.run("/usr/bin/sqlite3", [index, "VACUUM;"])
                if !r.success { return .failed(r.error ?? "Could not compact") }
            }
            return .done("Compacted")
        default:
            return .skipped("Unknown task")
        }
    }

    static func brokenLaunchAgents() -> [String] {
        Paths.children(of: Paths.home + "/Library/LaunchAgents").filter { plist in
            guard plist.hasSuffix(".plist"),
                  let dict = NSDictionary(contentsOfFile: plist) as? [String: Any] else { return false }
            let program = (dict["Program"] as? String) ?? (dict["ProgramArguments"] as? [String])?.first
            guard let program, program.hasPrefix("/") else { return false }
            return !FileManager.default.fileExists(atPath: program)
        }
    }

    static func corruptPreferences() -> [String] {
        Paths.children(of: Paths.home + "/Library/Preferences").filter { path in
            guard path.hasSuffix(".plist"), let data = FileManager.default.contents(atPath: path) else { return false }
            if data.isEmpty { return false }
            return (try? PropertyListSerialization.propertyList(from: data, format: nil)) == nil
        }
    }

    // MARK: Touch ID for sudo

    static let sudoLocal = "/etc/pam.d/sudo_local"

    func refreshTouchID() {
        let text = (try? String(contentsOfFile: Self.sudoLocal, encoding: .utf8)) ?? ""
        touchIDEnabled = text.split(separator: "\n").contains { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return !t.hasPrefix("#") && t.contains("pam_tid.so")
        }
    }

    func setTouchID(_ enabled: Bool) {
        guard !touchIDBusy else { return }
        touchIDBusy = true
        let script = enabled
            ? "if [ -f /etc/pam.d/sudo_local.template ]; then /usr/bin/sed 's/^#auth/auth/' /etc/pam.d/sudo_local.template > \(Self.sudoLocal); else echo 'auth       sufficient     pam_tid.so' > \(Self.sudoLocal); fi"
            : "/usr/bin/sed -i '' '/pam_tid.so/s/^auth/#auth/' \(Self.sudoLocal)"
        Task { @MainActor in
            _ = await Shell.runAsAdmin(script)
            refreshTouchID()
            touchIDBusy = false
        }
    }
}
