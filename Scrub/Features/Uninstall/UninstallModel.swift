import AppKit
import Observation

@Observable
final class UninstallModel {
    enum Sort: String, CaseIterable, Identifiable {
        case name = "Name", size = "Size", lastUsed = "Last Used"
        var id: String { rawValue }
    }

    var apps: [InstalledApp] = []
    var sizes: [String: Int64] = [:]
    var isLoading = false
    var search = ""
    var sort: Sort = .size
    var selection: Set<String> = []

    var leftovers: [String: [Leftover]] = [:]
    var excludedLeftovers: Set<String> = []
    var loadingLeftovers: Set<String> = []

    var isRemoving = false
    var removalStatus = ""
    var lastResult: (count: Int, bytes: Int64)?

    var visibleApps: [InstalledApp] {
        let filtered = search.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search)
        }
        switch sort {
        case .name: return filtered
        case .size: return filtered.sorted { (sizes[$0.path] ?? 0) > (sizes[$1.path] ?? 0) }
        case .lastUsed: return filtered.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
    }

    var selectedApps: [InstalledApp] { apps.filter { selection.contains($0.path) } }

    func totalSize(of app: InstalledApp) -> Int64 {
        (sizes[app.path] ?? 0) + (leftovers[app.path] ?? []).filter { !excludedLeftovers.contains($0.path) }.reduce(0) { $0 + $1.size }
    }

    var selectionTotal: Int64 { selectedApps.reduce(0) { $0 + totalSize(of: $1) } }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let apps = AppInventory.load()
            await MainActor.run {
                self?.apps = apps
                self?.isLoading = false
            }
            let lock = NSLock()
            var sizes: [String: Int64] = [:]
            DispatchQueue.concurrentPerform(iterations: apps.count) { i in
                let s = FileSizer.allocatedSize(atPath: apps[i].path)
                lock.lock(); sizes[apps[i].path] = s; lock.unlock()
            }
            await MainActor.run { self?.sizes = sizes }
        }
    }

    func loadLeftovers(for app: InstalledApp) {
        guard leftovers[app.path] == nil, !loadingLeftovers.contains(app.path) else { return }
        loadingLeftovers.insert(app.path)
        Task.detached(priority: .userInitiated) { [weak self] in
            let found = LeftoverFinder.find(for: app)
            await MainActor.run {
                guard let self else { return }
                self.leftovers[app.path] = found
                for l in found where !l.selectedByDefault { self.excludedLeftovers.insert(l.path) }
                self.loadingLeftovers.remove(app.path)
            }
        }
    }

    /// Uninstalls the selected apps, or with `keepApp` only resets their data.
    func removeSelected(keepApp: Bool = false) {
        let targets = selectedApps
        guard !targets.isEmpty, !isRemoving else { return }
        isRemoving = true
        let excluded = excludedLeftovers
        let leftoverMap = leftovers
        Task.detached(priority: .userInitiated) { [weak self] in
            var report = RemovalReport()
            for app in targets {
                await MainActor.run { self?.removalStatus = "Removing \(app.name)…" }
                await Self.quit(app)
                var userPaths: [String] = []
                var adminPaths: [String] = []
                let items = (leftoverMap[app.path] ?? LeftoverFinder.find(for: app)).filter { !excluded.contains($0.path) }
                for item in items {
                    if item.requiresAdmin { adminPaths.append(item.path) } else { userPaths.append(item.path) }
                }
                if !keepApp { userPaths.insert(app.path, at: 0) }
                let r = Remover.remove(userPaths, mode: .trash)
                report.merge(r)
                adminPaths += r.needsAdmin
                if !adminPaths.isEmpty {
                    report.needsAdmin = []
                    report.merge(await Remover.removeWithAdmin(adminPaths, mode: .trash))
                }
                if !keepApp { Self.removeFromDock(app) }
            }
            let final = report
            await MainActor.run {
                guard let self else { return }
                self.isRemoving = false
                self.removalStatus = ""
                self.lastResult = (targets.count, final.freedBytes)
                let removedApps = keepApp ? [] : targets.filter { !FileManager.default.fileExists(atPath: $0.path) }
                self.apps.removeAll { a in removedApps.contains(where: { $0.path == a.path }) }
                for app in targets {
                    self.leftovers[app.path] = nil
                    self.selection.remove(app.path)
                }
                let names = targets.map(\.name).joined(separator: ", ")
                HistoryStore.shared.record(.uninstall, title: keepApp ? "Reset \(names)" : "Uninstalled \(names)",
                                           bytes: final.freedBytes, items: final.removed.count,
                                           details: final.removed.map(Paths.abbreviate))
            }
        }
    }

    static func quit(_ app: InstalledApp) async {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
        guard !running.isEmpty else { return }
        running.forEach { $0.terminate() }
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            if running.allSatisfy(\.isTerminated) { return }
        }
        running.forEach { $0.forceTerminate() }
        try? await Task.sleep(for: .milliseconds(300))
    }

    /// Removes the app's tile from the Dock if it was pinned there.
    static func removeFromDock(_ app: InstalledApp) {
        guard let dock = UserDefaults(suiteName: "com.apple.dock"),
              var persistent = dock.array(forKey: "persistent-apps") as? [[String: Any]] else { return }
        let before = persistent.count
        persistent.removeAll { tile in
            let data = tile["tile-data"] as? [String: Any]
            return (data?["bundle-identifier"] as? String) == app.bundleID
        }
        guard persistent.count != before else { return }
        dock.set(persistent, forKey: "persistent-apps")
        dock.synchronize()
        _ = Shell.runSync("/usr/bin/killall", ["Dock"])
    }
}
