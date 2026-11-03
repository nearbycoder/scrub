import Foundation

/// Convenience wrappers around `DiskWalker` for one-off measurements.
enum FileSizer {
    static func allocatedSize(atPath path: String) -> Int64 { DiskWalker.size(of: path) }

    /// Most recent modification time directly inside a directory (non-recursive), including the directory itself.
    static func shallowLastModified(_ url: URL) -> Date? {
        var latest = Paths.modificationDate(url.path)
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        DiskWalker.readDirectory(url.path, buffer: &buffer) { entry in
            let d = Date(timeIntervalSince1970: TimeInterval(entry.modified))
            if d > (latest ?? .distantPast) { latest = d }
        }
        return latest
    }
}

extension Int {
    /// "1 file", "3 files". Pass `plural` for nouns that don't just take an "s".
    func counted(_ singular: String, _ plural: String? = nil) -> String {
        "\(formatted()) \(self == 1 ? singular : plural ?? singular + "s")"
    }
}

extension Int64 {
    /// Sizes the way Finder writes them ("1.2 GB", "0 KB").
    var formattedBytes: String { Self.byteFormatter.string(fromByteCount: self) }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f
    }()
}

extension Date {
    var relativeDescription: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: self, relativeTo: .now)
    }

    var daysAgo: Int {
        Calendar.current.dateComponents([.day], from: self, to: .now).day ?? 0
    }
}
