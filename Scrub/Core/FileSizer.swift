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

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
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
