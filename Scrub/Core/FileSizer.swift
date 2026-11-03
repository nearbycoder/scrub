import Foundation

/// Fast, hardlink-aware disk usage measurement built on `fts(3)`.
enum FileSizer {
    /// Allocated bytes on disk for a file or directory tree. Symlinks are not followed and
    /// traversal stays on the starting volume. Files with several hard links are counted once.
    static func allocatedSize(atPath path: String, isCancelled: () -> Bool = { false }) -> Int64 {
        var total: Int64 = 0
        var seenInodes = Set<UInt64>()
        walk(path) { entry, stat in
            if entry == .file {
                if stat.st_nlink > 1, !seenInodes.insert(stat.st_ino).inserted { return true }
                total += Int64(stat.st_blocks) * 512
            }
            return !isCancelled()
        }
        return total
    }

    static func allocatedSize(of url: URL) -> Int64 {
        allocatedSize(atPath: url.path)
    }

    enum Entry { case directoryPre, directoryPost, file, unreadable, skipped }

    /// Low-level traversal. Return `false` from the visitor to stop.
    /// The visitor also receives the fts level (0 for the root).
    static func walk(_ path: String, visit: (Entry, stat) -> Bool) {
        walkDetailed(path) { entry, st, _, _, _ in visit(entry, st) }
    }

    /// `skip` is consulted for each directory; skipped directories are reported as `.skipped`
    /// and are still followed by a `.directoryPost` visit.
    static func walkDetailed(
        _ path: String,
        crossDevices: Bool = false,
        skip: ((String) -> Bool)? = nil,
        visit: (_ entry: Entry, _ stat: stat, _ level: Int, _ path: UnsafePointer<CChar>, _ name: String?) -> Bool
    ) {
        guard let root = strdup(path) else { return }
        defer { free(root) }
        var paths: [UnsafeMutablePointer<CChar>?] = [root, nil]
        var options = FTS_PHYSICAL | FTS_NOCHDIR
        if !crossDevices { options |= FTS_XDEV }
        guard let fts = fts_open(&paths, options, nil) else { return }
        defer { fts_close(fts) }

        var lastPreOrder: UnsafeMutablePointer<FTSENT>?
        while let ent = fts_read(fts) {
            let info = Int32(ent.pointee.fts_info)
            let level = Int(ent.pointee.fts_level)
            var st = stat()
            if let sp = ent.pointee.fts_statp { st = sp.pointee }
            let entry: Entry
            switch info {
            case FTS_D: entry = .directoryPre; lastPreOrder = ent
            case FTS_DP: entry = .directoryPost
            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT: entry = .file
            case FTS_DNR, FTS_ERR, FTS_NS:
                // A directory that can't be read comes back as FTS_D followed by FTS_DNR in place
                // of FTS_DP. Report it as unreadable and then close it so callers stay balanced.
                if ent == lastPreOrder {
                    lastPreOrder = nil
                    if !visit(.unreadable, st, level, ent.pointee.fts_path, nil) { return }
                    if !visit(.directoryPost, st, level, ent.pointee.fts_path, nil) { return }
                    continue
                }
                entry = .unreadable
            default: continue
            }
            var reported = entry
            if entry == .directoryPre, level > 0, let skip, skip(String(cString: ent.pointee.fts_path)) {
                fts_set(fts, ent, FTS_SKIP)
                reported = .skipped
            }
            if !visit(reported, st, level, ent.pointee.fts_path, nil) { break }
        }
    }

    /// Most recent modification time found directly inside a directory (non-recursive),
    /// including the directory itself.
    static func shallowLastModified(_ url: URL) -> Date? {
        let fm = FileManager.default
        var latest = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let children = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey], options: []) {
            for child in children {
                if let d = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                   d > (latest ?? .distantPast) {
                    latest = d
                }
            }
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
