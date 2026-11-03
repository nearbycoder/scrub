import SwiftUI
import Observation

struct CleanItem: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let size: Int64
    let modified: Date?
    var name: String { (path as NSString).lastPathComponent }
    var modifiedSort: Date { modified ?? .distantPast }
}

@Observable
final class CleanRuleResult: Identifiable {
    let rule: CleanRule
    var items: [CleanItem]
    var excluded: Set<String> = []
    var isSelected: Bool
    var blockedBy: String?

    var id: String { rule.id }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedItems: [CleanItem] { items.filter { !excluded.contains($0.path) } }
    var selectedSize: Int64 { isActive ? selectedItems.reduce(0) { $0 + $1.size } : 0 }
    var isActive: Bool { isSelected && blockedBy == nil }

    init(rule: CleanRule, items: [CleanItem], isSelected: Bool, blockedBy: String?) {
        self.rule = rule
        self.items = items
        self.isSelected = isSelected
        self.blockedBy = blockedBy
    }
}

@Observable
final class CleanModel {
    enum Phase: Equatable {
        case idle, scanning, ready, cleaning, finished
    }

    var phase: Phase = .idle
    var results: [CleanRuleResult] = [] { didSet { rebuildIndex() } }
    private(set) var resultByID: [String: CleanRuleResult] = [:]
    var selectedRuleID: String?
    var progress: Double = 0
    var currentStep = ""
    var scannedFiles = 0
    var scannedBytes: Int64 = 0
    var lastReport: RemovalReport?
    var lastFreed: Int64 = 0
    var lastScanDate: Date?
    var skippedForAccess = 0
    var scanDuration: TimeInterval = 0

    var totalFound: Int64 { results.reduce(0) { $0 + $1.totalSize } }
    var totalSelected: Int64 { results.reduce(0) { $0 + $1.selectedSize } }
    var selectedItemCount: Int { results.filter(\.isActive).reduce(0) { $0 + $1.selectedItems.count } }

    func results(in group: CleanGroup) -> [CleanRuleResult] { results.filter { $0.rule.group == group } }
    func size(of group: CleanGroup) -> Int64 { results(in: group).reduce(0) { $0 + $1.totalSize } }
    func selectedSize(of group: CleanGroup) -> Int64 { results(in: group).reduce(0) { $0 + $1.selectedSize } }

    private func rebuildIndex() {
        resultByID = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
        if selectedRuleID.map({ resultByID[$0] == nil }) ?? true {
            selectedRuleID = results.first(where: \.isActive)?.id ?? results.first?.id
        }
    }

    func scan() {
        guard phase != .scanning && phase != .cleaning else { return }
        phase = .scanning
        progress = 0
        scannedFiles = 0
        scannedBytes = 0
        currentStep = "Looking for junk"
        results = []
        lastReport = nil
        let settings = AppSettings.shared
        let running = settings.skipRunningApps ? SystemAccess.runningBundleIDs : []
        let runningNames = Dictionary(NSWorkspace.shared.runningApplications.compactMap { app in
            app.bundleIdentifier.map { ($0, app.localizedName ?? $0) }
        }, uniquingKeysWith: { a, _ in a })
        let disabled = settings.disabledCleanRules
        let enabled = settings.enabledCleanRules
        let protected = settings.protectedPaths
        let fullDiskAccess = SystemAccess.hasFullDiskAccess
        let walkProgress = DiskWalker.Progress()
        let started = Date()

        // Poll the walker's counters instead of hopping to the main actor for every directory.
        Task { @MainActor [weak self] in
            while let self, self.phase == .scanning {
                self.scannedFiles = walkProgress.files
                self.scannedBytes = walkProgress.bytes
                try? await Task.sleep(for: .milliseconds(120))
            }
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            let rules = CleanCatalog.rules
            // Roots of every rule, used so broad rules never swallow a more specific one.
            var roots: [String: [String]] = [:]
            var skipped = 0
            for rule in rules {
                let all = rule.paths.flatMap(Paths.glob).filter { !Paths.leavesStartupDisk($0) }
                let allowed = fullDiskAccess ? all : all.filter { !SystemAccess.isPrivacyProtected($0) }
                skipped += all.count - allowed.count
                roots[rule.id] = allowed
            }
            let allRoots = roots.flatMap { id, paths in paths.map { ($0, id) } }

            // 1. Find candidates for every rule (cheap directory listings, in parallel).
            var candidates = [[String]](repeating: [], count: rules.count)
            let lock = NSLock()
            let installed = AppInventory.installedBundleIDs()
            DispatchQueue.concurrentPerform(iterations: rules.count) { index in
                let rule = rules[index]
                let found: [String]
                if rule.id == "orphans" {
                    found = OrphanFinder.candidates(installed: installed, fullDiskAccess: fullDiskAccess)
                } else {
                    let others = allRoots.filter { $0.1 != rule.id }.map(\.0)
                    found = Self.candidates(rule: rule, roots: roots[rule.id] ?? [], otherRoots: others,
                                            running: running, protected: protected)
                }
                lock.lock(); candidates[index] = found; lock.unlock()
            }
            await MainActor.run { self?.currentStep = "Measuring"; self?.progress = 0.3 }

            // 2. Measure everything in one parallel walk.
            let skip: ((String) -> Bool)? = fullDiskAccess ? nil : { SystemAccess.isPrivacyProtected($0) }
            let measured = DiskWalker.measure(candidates.flatMap { $0 }, skip: skip, progress: walkProgress)

            // 3. Assemble results.
            var collected: [CleanRuleResult] = []
            for (index, rule) in rules.enumerated() {
                let cutoff = rule.minAgeDays.map { Date().addingTimeInterval(-Double($0) * 86_400) }
                var items: [CleanItem] = []
                for path in candidates[index] {
                    guard let m = measured[path] else { continue }
                    if let cutoff, let newest = m.newest, newest > cutoff { continue }
                    if m.size < 4096 && rule.group != .trash { continue }
                    items.append(CleanItem(path: path, size: m.size, modified: m.newest))
                }
                guard !items.isEmpty else { continue }
                let blocking = rule.bundleIDs.first { running.contains($0) }
                var selected = rule.selectedByDefault
                if disabled.contains(rule.id) { selected = false }
                if enabled.contains(rule.id) { selected = true }
                collected.append(CleanRuleResult(rule: rule, items: items.sorted { $0.size > $1.size }, isSelected: selected,
                                                 blockedBy: blocking.map { "\(runningNames[$0] ?? $0) is open" }))
            }
            let skippedCount = skipped
            await MainActor.run {
                guard let self else { return }
                self.skippedForAccess = skippedCount
                self.results = collected
                self.phase = .ready
                self.progress = 1
                self.lastScanDate = .now
                self.scanDuration = Date().timeIntervalSince(started)
                self.scannedFiles = walkProgress.files
                self.scannedBytes = walkProgress.bytes
            }
        }
    }

    /// Lists the paths a rule would remove, before measuring them.
    static func candidates(rule: CleanRule, roots: [String], otherRoots: [String],
                           running: Set<String>, protected: [String]) -> [String] {
        let isProtected: (String) -> Bool = { path in
            protected.contains { let p = Paths.expand($0); return path == p || path.hasPrefix(p + "/") }
        }
        var raw: [String] = []
        switch rule.scope {
        case .items:
            raw = roots
        case .contents:
            for root in roots where Paths.isDirectory(root) && !isProtected(root) {
                for child in Paths.children(of: root) {
                    let name = (child as NSString).lastPathComponent
                    if rule.excludeNames.contains(name) || name == ".DS_Store" || name == ".localized" { continue }
                    if let exts = rule.extensions, !exts.contains((name as NSString).pathExtension.lowercased()) { continue }
                    raw.append(child)
                }
            }
        }
        var seen = Set<String>()
        return raw.filter { path in
            guard seen.insert(path).inserted else { return false }
            // A broad rule (like all user caches) must not contain a narrower rule's target.
            if otherRoots.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) { return false }
            let name = (path as NSString).lastPathComponent
            if running.contains(where: { name == $0 || name.hasPrefix($0 + ".") || name == $0 + ".savedState" }) { return false }
            return !isProtected(path) && PathGuard.isAllowed(path)
        }
    }

    func clean() {
        guard phase == .ready else { return }
        let active = results.filter(\.isActive)
        guard !active.isEmpty else { return }
        phase = .cleaning
        progress = 0
        let mode = AppSettings.shared.cacheRemovalMode
        let work = active.map { r in (r.rule, r.selectedItems) }

        Task.detached(priority: .userInitiated) { [weak self] in
            var report = RemovalReport()
            for (index, (rule, items)) in work.enumerated() {
                await MainActor.run { self?.currentStep = rule.name }
                let keepsUndo = rule.group == .separately || rule.group == .leftovers || rule.group == .installers
                let ruleMode: RemovalMode = rule.group == .trash ? .permanent : (keepsUndo ? .trash : mode)
                var sizes: [String: Int64] = [:]
                for item in items { sizes[item.path] = item.size }
                report.merge(Remover.remove(items.map(\.path), mode: ruleMode, sizes: sizes))
                let p = Double(index + 1) / Double(work.count)
                await MainActor.run { self?.progress = p }
            }
            if !report.needsAdmin.isEmpty {
                await MainActor.run { self?.currentStep = "Removing protected items" }
                let adminReport = await Remover.removeWithAdmin(report.needsAdmin, mode: .trash)
                report.needsAdmin = []
                report.merge(adminReport)
            }
            let final = report
            await MainActor.run {
                guard let self else { return }
                self.lastReport = final
                self.lastFreed = final.freedBytes
                self.phase = .finished
                HistoryStore.shared.record(.clean, title: "Cleaned \(work.count.counted("category", "categories"))",
                                           bytes: final.freedBytes, items: final.removed.count,
                                           details: final.removed.map(Paths.abbreviate))
            }
        }
    }

    func setSelected(_ result: CleanRuleResult, _ selected: Bool) {
        result.isSelected = selected
        let settings = AppSettings.shared
        if selected == result.rule.selectedByDefault {
            settings.disabledCleanRules.remove(result.rule.id)
            settings.enabledCleanRules.remove(result.rule.id)
        } else if selected {
            settings.enabledCleanRules.insert(result.rule.id)
            settings.disabledCleanRules.remove(result.rule.id)
        } else {
            settings.disabledCleanRules.insert(result.rule.id)
            settings.enabledCleanRules.remove(result.rule.id)
        }
    }

    func reset() {
        phase = .idle
        results = []
        progress = 0
    }
}

enum OrphanFinder {
    static let locations: [(dir: String, suffix: String?)] = [
        // Caches and Logs are already covered by the general rules.
        ("~/Library/Application Support", nil), ("~/Library/Containers", nil),
        ("~/Library/Preferences", ".plist"), ("~/Library/Saved Application State", ".savedState"),
        ("~/Library/HTTPStorages", nil), ("~/Library/WebKit", nil),
        ("~/Library/Application Scripts", nil), ("~/Library/Cookies", ".binarycookies"),
    ]

    static let ignoredPrefixes = ["com.apple.", "group.", "systemgroup.", "com.nearbycoder.scrub"]

    /// Paths that look like data from apps that are no longer installed. Sizes are measured later.
    static func candidates(installed: Set<String>, fullDiskAccess: Bool) -> [String] {
        let installedPrefixes = Set(installed.map { vendorProduct($0) })
        // Data from a vendor that still has an app installed is often shared or migrated; leave it alone.
        let installedVendors = Set(installed.filter { !$0.hasPrefix("com.apple.") }.map { vendor($0) })
        let cutoff = Date().addingTimeInterval(-15 * 86_400)
        var found: [String] = []
        for (dir, suffix) in locations {
            if !fullDiskAccess && SystemAccess.isPrivacyProtected(Paths.expand(dir) + "/") { continue }
            for path in Paths.children(of: Paths.expand(dir)) {
                var name = (path as NSString).lastPathComponent
                if let suffix {
                    guard name.hasSuffix(suffix) else { continue }
                    name = String(name.dropLast(suffix.count))
                }
                guard isBundleIdentifier(name), !ignoredPrefixes.contains(where: name.hasPrefix) else { continue }
                if installed.contains(name) || installedPrefixes.contains(vendorProduct(name)) { continue }
                if installedVendors.contains(vendor(name)) { continue }
                if installed.contains(where: { name.hasPrefix($0 + ".") }) { continue }
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) != nil { continue }
                let modified = Paths.isDirectory(path) ? FileSizer.shallowLastModified(URL(fileURLWithPath: path)) : Paths.modificationDate(path)
                if let modified, modified > cutoff { continue }
                guard PathGuard.isAllowed(path) else { continue }
                found.append(path)
            }
        }
        return found
    }

    static func isBundleIdentifier(_ s: String) -> Bool {
        let parts = s.split(separator: ".")
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }) else { return false }
        guard let tld = parts.first, tld.count <= 6, tld.allSatisfy({ $0.isLetter }) else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_" }
    }

    static func vendor(_ id: String) -> String {
        id.split(separator: ".").prefix(2).joined(separator: ".").lowercased()
    }

    static func vendorProduct(_ id: String) -> String {
        id.split(separator: ".").prefix(3).joined(separator: ".").lowercased()
    }
}
