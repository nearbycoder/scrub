import Foundation

enum RemovalMode: String, Codable, CaseIterable, Identifiable {
    case trash, permanent
    var id: String { rawValue }
    var label: String { self == .trash ? "Move to Trash" : "Delete permanently" }
}

struct RemovalReport {
    var freedBytes: Int64 = 0
    var removed: [String] = []
    var failures: [(path: String, reason: String)] = []
    var needsAdmin: [String] = []

    mutating func merge(_ other: RemovalReport) {
        freedBytes += other.freedBytes
        removed += other.removed
        failures += other.failures
        needsAdmin += other.needsAdmin
    }
}

enum Remover {
    /// Removes items, never touching anything PathGuard rejects.
    /// `sizes` lets callers report freed space without re-measuring.
    static func remove(_ paths: [String], mode: RemovalMode, sizes: [String: Int64] = [:]) -> RemovalReport {
        var report = RemovalReport()
        let fm = FileManager.default
        for path in paths {
            if case .denied(let reason) = PathGuard.check(path) {
                report.failures.append((path, reason))
                continue
            }
            guard fm.fileExists(atPath: path) || (try? fm.destinationOfSymbolicLink(atPath: path)) != nil else { continue }
            let size = sizes[path] ?? FileSizer.allocatedSize(atPath: path)
            do {
                if mode == .trash {
                    try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                } else {
                    try fm.removeItem(atPath: path)
                }
                report.freedBytes += size
                report.removed.append(path)
            } catch let error as NSError {
                if error.domain == NSCocoaErrorDomain,
                   [NSFileWriteNoPermissionError, NSFileWriteVolumeReadOnlyError].contains(error.code) || error.code == 513 {
                    report.needsAdmin.append(path)
                } else if mode == .permanent, (try? fm.contentsOfDirectory(atPath: path)) != nil {
                    // Partially removable directories (e.g. a locked file inside): remove what we can.
                    let partial = removeContents(path)
                    report.freedBytes += max(0, size - FileSizer.allocatedSize(atPath: path))
                    if !partial { report.failures.append((path, error.localizedDescription)) } else { report.removed.append(path) }
                } else {
                    report.failures.append((path, error.localizedDescription))
                }
            }
        }
        return report
    }

    @discardableResult
    private static func removeContents(_ path: String) -> Bool {
        var ok = true
        for child in Paths.children(of: path) {
            if (try? FileManager.default.removeItem(atPath: child)) == nil { ok = false }
        }
        return ok
    }

    /// Removes root-owned items with a single administrator prompt. Items go to the user's Trash
    /// when `mode == .trash`, otherwise they are deleted.
    static func removeWithAdmin(_ paths: [String], mode: RemovalMode) async -> RemovalReport {
        var report = RemovalReport()
        let allowed = paths.filter { PathGuard.isAllowed($0) }
        guard !allowed.isEmpty else { return report }
        var sizes: [String: Int64] = [:]
        for p in allowed { sizes[p] = FileSizer.allocatedSize(atPath: p) }
        let trash = Paths.home + "/.Trash"
        let commands = allowed.map { p -> String in
            let q = Shell.quote(p)
            if mode == .trash {
                let dest = Shell.quote(trash + "/" + (p as NSString).lastPathComponent + " \(Int(Date().timeIntervalSince1970))")
                return "/bin/mv -f \(q) \(dest) && /usr/sbin/chown -R \(getuid()) \(dest) && echo OK:\(q)"
            }
            return "/bin/rm -rf \(q) && echo OK:\(q)"
        }
        let result = await Shell.runAsAdmin(commands.joined(separator: "; "))
        for p in allowed {
            if !FileManager.default.fileExists(atPath: p) {
                report.removed.append(p)
                report.freedBytes += sizes[p] ?? 0
            } else {
                report.failures.append((p, result.success ? "Could not remove" : (result.error ?? "Cancelled")))
            }
        }
        return report
    }
}
