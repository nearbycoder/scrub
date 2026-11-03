import SwiftUI
import Observation

struct CleanItem: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let size: Int64
    let modified: Date?
    var name: String { (path as NSString).lastPathComponent }
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
    var results: [CleanRuleResult] = []
    var progress: Double = 0
    var currentStep = ""
    var lastReport: RemovalReport?
    var lastFreed: Int64 = 0
    var lastScanDate: Date?
    var skippedForAccess = 0

    var totalFound: Int64 { results.reduce(0) { $0 + $1.totalSize } }
    var totalSelected: Int64 { results.reduce(0) { $0 + $1.selectedSize } }
    var selectedItemCount: Int { results.filter(\.isActive).reduce(0) { $0 + $1.selectedItems.count } }

    func results(in group: CleanGroup) -> [CleanRuleResult] { results.filter { $0.rule.group == group } }
    func size(of group: CleanGroup) -> Int64 { results(in: group).reduce(0) { $0 + $1.totalSize } }
    func selectedSize(of group: CleanGroup) -> Int64 { results(in: group).reduce(0) { $0 + $1.selectedSize } }

    func scan() {
        guard phase != .scanning && phase != .cleaning else { return }
        phase = .scanning
        progress = 0
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
            let installed = rules.contains(where: { $0.id == "orphans" }) ? AppInventory.installedBundleIDs() : []

            var finished = 0
            let lock = NSLock()
            var collected: [CleanRuleResult] = []
            DispatchQueue.concurrentPerform(iterations: rules.count) { index in
                let rule = rules[index]
                let otherRoots = roots.filter { $0.key != rule.id }.flatMap(\.value)
                let items: [CleanItem]
                if rule.id == "orphans" {
                    items = OrphanFinder.find(installed: installed, fullDiskAccess: fullDiskAccess)
                } else {
                    items = Self.collect(rule: rule, roots: roots[rule.id] ?? [], otherRoots: otherRoots,
                                         running: running, protected: protected)
                }
                let blocking = rule.bundleIDs.first { running.contains($0) }
                let blockedBy = blocking.map { "\(runningNames[$0] ?? $0) is open" }
                var selected = rule.selectedByDefault
                if disabled.contains(rule.id) { selected = false }
                if enabled.contains(rule.id) { selected = true }
                let result = CleanRuleResult(rule: rule, items: items.sorted { $0.size > $1.size },
                                             isSelected: selected, blockedBy: blockedBy)
                lock.lock()
                if !items.isEmpty { collected.append(result) }
                finished += 1
                let p = Double(finished) / Double(rules.count)
                lock.unlock()
                Task { @MainActor in
                    self?.progress = max(self?.progress ?? 0, p)
                    self?.currentStep = rule.name
                }
            }
            let order = Dictionary(uniqueKeysWithValues: rules.enumerated().map { ($1.id, $0) })
            let sorted = collected.sorted { (order[$0.rule.id] ?? 0) < (order[$1.rule.id] ?? 0) }
            let skippedCount = skipped
            await MainActor.run {
                guard let self else { return }
                self.skippedForAccess = skippedCount
                self.results = sorted
                self.phase = .ready
                self.progress = 1
                self.lastScanDate = .now
            }
        }
    }

    static func collect(rule: CleanRule, roots: [String], otherRoots: [String],
                                    running: Set<String>, protected: [String]) -> [CleanItem] {
        let isProtected: (String) -> Bool = { path in
            protected.contains { let p = Paths.expand($0); return path == p || path.hasPrefix(p + "/") }
        }
        var candidates: [String] = []
        switch rule.scope {
        case .items:
            candidates = roots
        case .contents:
            for root in roots where Paths.isDirectory(root) && !isProtected(root) {
                for child in Paths.children(of: root) {
                    let name = (child as NSString).lastPathComponent
                    if rule.excludeNames.contains(name) || name == ".DS_Store" || name == ".localized" { continue }
                    if let exts = rule.extensions, !exts.contains((name as NSString).pathExtension.lowercased()) { continue }
                    candidates.append(child)
                }
            }
        }

        let cutoff = rule.minAgeDays.map { Date().addingTimeInterval(-Double($0) * 86_400) }
        var items: [CleanItem] = []
        var seen = Set<String>()
        for path in candidates where seen.insert(path).inserted {
            // A broad rule (like all user caches) must not contain a narrower rule's target.
            if otherRoots.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) { continue }
            let name = (path as NSString).lastPathComponent
            if running.contains(where: { name == $0 || name.hasPrefix($0 + ".") || name == $0 + ".savedState" }) { continue }
            if isProtected(path) { continue }
            if !PathGuard.isAllowed(path) { continue }
            let modified = Paths.isDirectory(path) ? FileSizer.shallowLastModified(URL(fileURLWithPath: path)) : Paths.modificationDate(path)
            if let cutoff, let modified, modified > cutoff { continue }
            let size = FileSizer.allocatedSize(atPath: path)
            if size < 4096 && rule.group != .trash { continue }
            items.append(CleanItem(path: path, size: size, modified: modified))
        }
        return items
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
                let ruleMode: RemovalMode = rule.group == .trash ? .permanent : (rule.group == .separately || rule.group == .leftovers || rule.group == .installers ? .trash : mode)
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
                HistoryStore.shared.record(.clean, title: "Cleaned \(work.count) categories",
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

    static func find(installed: Set<String>, fullDiskAccess: Bool) -> [CleanItem] {
        let installedPrefixes = Set(installed.map { vendorProduct($0) })
        // Data from a vendor that still has an app installed is often shared or migrated; leave it alone.
        let installedVendors = Set(installed.filter { !$0.hasPrefix("com.apple.") }.map { vendor($0) })
        let cutoff = Date().addingTimeInterval(-15 * 86_400)
        var items: [CleanItem] = []
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
                let size = FileSizer.allocatedSize(atPath: path)
                if size < 4096 { continue }
                items.append(CleanItem(path: path, size: size, modified: modified))
            }
        }
        return items
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
