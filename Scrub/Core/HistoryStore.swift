import Foundation
import Observation

struct HistoryEntry: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case clean, uninstall, analyze, optimize, purge, installers
        var label: String {
            switch self {
            case .clean: "Clean"
            case .uninstall: "Uninstall"
            case .analyze: "Space Lens"
            case .optimize: "Optimize"
            case .purge: "Purge"
            case .installers: "Installers"
            }
        }
        var symbol: String {
            switch self {
            case .clean: "sparkles"
            case .uninstall: "trash.square"
            case .analyze: "square.grid.3x3.square"
            case .optimize: "bolt.heart"
            case .purge: "shippingbox"
            case .installers: "externaldrive.badge.minus"
            }
        }
    }

    var id = UUID()
    var date = Date()
    var kind: Kind
    var title: String
    var bytesFreed: Int64
    var itemCount: Int
    var details: [String] = []
}

@Observable
final class HistoryStore {
    static let shared = HistoryStore()
    private(set) var entries: [HistoryEntry] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scrub", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    var totalFreed: Int64 { entries.reduce(0) { $0 + $1.bytesFreed } }

    func record(_ kind: HistoryEntry.Kind, title: String, bytes: Int64, items: Int, details: [String] = []) {
        guard bytes > 0 || items > 0 else { return }
        entries.insert(HistoryEntry(kind: kind, title: title, bytesFreed: bytes, itemCount: items,
                                    details: Array(details.prefix(500))), at: 0)
        if entries.count > 1000 { entries.removeLast(entries.count - 1000) }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url, options: .atomic) }
    }
}
