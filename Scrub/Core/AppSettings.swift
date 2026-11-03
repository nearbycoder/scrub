import Foundation
import Observation

@Observable
final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    var cacheRemovalMode: RemovalMode {
        didSet { defaults.set(cacheRemovalMode.rawValue, forKey: "cacheRemovalMode") }
    }
    var purgeRemovalMode: RemovalMode {
        didSet { defaults.set(purgeRemovalMode.rawValue, forKey: "purgeRemovalMode") }
    }
    var protectedPaths: [String] {
        didSet { defaults.set(protectedPaths, forKey: "protectedPaths") }
    }
    var projectRoots: [String] {
        didSet { defaults.set(projectRoots, forKey: "projectRoots") }
    }
    var showMenuBarExtra: Bool {
        didSet { defaults.set(showMenuBarExtra, forKey: "showMenuBarExtra") }
    }
    var purgeRecentDays: Int {
        didSet { defaults.set(purgeRecentDays, forKey: "purgeRecentDays") }
    }
    var installerAgeDays: Int {
        didSet { defaults.set(installerAgeDays, forKey: "installerAgeDays") }
    }
    var skipRunningApps: Bool {
        didSet { defaults.set(skipRunningApps, forKey: "skipRunningApps") }
    }
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }
    var disabledCleanRules: Set<String> {
        didSet { defaults.set(Array(disabledCleanRules), forKey: "disabledCleanRules") }
    }
    var enabledCleanRules: Set<String> {
        didSet { defaults.set(Array(enabledCleanRules), forKey: "enabledCleanRules") }
    }

    static let defaultProjectRoots = ["~/Projects", "~/GitHub", "~/Developer", "~/dev", "~/code", "~/src", "~/workspace", "~/repos", "~/Sites"]

    private init() {
        cacheRemovalMode = RemovalMode(rawValue: defaults.string(forKey: "cacheRemovalMode") ?? "") ?? .permanent
        purgeRemovalMode = RemovalMode(rawValue: defaults.string(forKey: "purgeRemovalMode") ?? "") ?? .permanent
        protectedPaths = defaults.stringArray(forKey: "protectedPaths") ?? []
        projectRoots = defaults.stringArray(forKey: "projectRoots") ?? Self.defaultProjectRoots
        showMenuBarExtra = defaults.object(forKey: "showMenuBarExtra") as? Bool ?? true
        purgeRecentDays = defaults.object(forKey: "purgeRecentDays") as? Int ?? 7
        installerAgeDays = defaults.object(forKey: "installerAgeDays") as? Int ?? 14
        skipRunningApps = defaults.object(forKey: "skipRunningApps") as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        disabledCleanRules = Set(defaults.stringArray(forKey: "disabledCleanRules") ?? [])
        enabledCleanRules = Set(defaults.stringArray(forKey: "enabledCleanRules") ?? [])
    }

    func isProtected(_ path: String) -> Bool {
        protectedPaths.contains { p in
            let e = Paths.expand(p)
            return path == e || path.hasPrefix(e + "/")
        }
    }
}
