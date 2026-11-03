import SwiftUI
import Observation

@Observable
final class AppState {
    static let shared = AppState()

    var section: AppSection = .overview
    let clean = CleanModel()
    let uninstall = UninstallModel()
    let analyze = AnalyzeModel()
    let optimize = OptimizeModel()
    let purge = PurgeModel()
    let installers = InstallersModel()
    let monitor = SystemMonitor.shared
    let history = HistoryStore.shared
    let settings = AppSettings.shared
    var hasFullDiskAccess = SystemAccess.hasFullDiskAccess

    private init() {
        // Launch arguments such as `-initialSection analyze -autoScan YES` are handy for demos and screenshots.
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "initialSection"), let s = AppSection(rawValue: raw) { section = s }
        if defaults.bool(forKey: "autoScan") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                switch section {
                case .clean, .overview: clean.scan()
                case .analyze:
                    if let path = defaults.string(forKey: "analyzePath") {
                        analyze.scan(.init(path: path, title: (path as NSString).lastPathComponent, symbol: "folder.fill"))
                    } else if let home = analyze.scopes.first { analyze.scan(home) }
                case .purge: purge.scan()
                case .uninstall: uninstall.load()
                default: break
                }
            }
        }
    }

    func refreshAccess() { hasFullDiskAccess = SystemAccess.hasFullDiskAccess }
}
