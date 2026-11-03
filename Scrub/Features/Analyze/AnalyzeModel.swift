import AppKit
import Observation

@Observable
final class AnalyzeModel {
    struct Scope: Identifiable, Hashable {
        let path: String
        let title: String
        let symbol: String
        var id: String { path }
    }

    var root: DiskNode?
    var current: DiskNode?
    var largeFiles: [LargeFile] = []
    var isScanning = false
    var scannedFiles = 0
    var scannedBytes: Int64 = 0
    var scope: Scope?
    var lastScan: Date?
    var hovered: DiskNode?
    private var scanTask: Task<Void, Never>?
    private var cancelFlag = CancelFlag()

    final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func cancel() { lock.lock(); value = true; lock.unlock() }
    }

    var scopes: [Scope] {
        var list = [
            Scope(path: Paths.home, title: "Home", symbol: "house.fill"),
            Scope(path: Paths.isDirectory("/System/Volumes/Data") ? "/System/Volumes/Data" : "/", title: "Macintosh HD", symbol: "internaldrive.fill"),
            Scope(path: "/Applications", title: "Applications", symbol: "square.grid.2x2.fill"),
            Scope(path: Paths.home + "/Library", title: "Library", symbol: "building.columns.fill"),
        ]
        let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeNameKey]
        for url in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        where url.path.hasPrefix("/Volumes/") {
            let name = (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? url.lastPathComponent
            list.append(Scope(path: url.path, title: name, symbol: "externaldrive.fill"))
        }
        return list
    }

    func scan(_ scope: Scope) {
        cancel()
        self.scope = scope
        isScanning = true
        scannedFiles = 0
        scannedBytes = 0
        root = nil
        current = nil
        largeFiles = []
        let flag = CancelFlag()
        cancelFlag = flag
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = DiskScanner.scan(scope.path, progress: { files, bytes in
                Task { @MainActor in
                    self?.scannedFiles = files
                    self?.scannedBytes = bytes
                }
            }, isCancelled: { flag.isCancelled })
            guard !flag.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                if scope.path == "/System/Volumes/Data" {
                    let r = result.root
                    let renamed = DiskNode(path: r.path, name: "Macintosh HD", isDirectory: true)
                    renamed.size = r.size; renamed.fileCount = r.fileCount; renamed.children = r.children
                    renamed.looseFileSize = r.looseFileSize; renamed.looseFileCount = r.looseFileCount
                    r.children.forEach { $0.parent = renamed }
                    self.root = renamed
                } else {
                    self.root = result.root
                }
                self.current = self.root
                self.largeFiles = result.largeFiles
                self.isScanning = false
                self.lastScan = .now
            }
        }
    }

    func scanCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Analyze"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scan(Scope(path: url.path, title: url.lastPathComponent, symbol: "folder.fill"))
    }

    func cancel() {
        cancelFlag.cancel()
        scanTask?.cancel()
        isScanning = false
    }

    func open(_ node: DiskNode) {
        guard node.isDirectory, !node.isSynthetic, !node.isUnreadable else { return }
        if node.isTruncated && node.children.isEmpty {
            rescan(node)
        }
        current = node
    }

    /// Re-scans a directory that was summarised beyond the depth limit and grafts the result in place.
    private func rescan(_ node: DiskNode) {
        isScanning = true
        let path = node.path
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = DiskScanner.scan(path, progress: { _, _ in }, isCancelled: { false })
            await MainActor.run {
                node.children = result.root.children
                node.children.forEach { $0.parent = node }
                node.looseFileSize = result.root.looseFileSize
                node.looseFileCount = result.root.looseFileCount
                node.isTruncated = false
                self?.isScanning = false
                if self?.current === node { self?.current = nil; self?.current = node }
            }
        }
    }

    func goUp() {
        if let parent = current?.parent { current = parent }
    }

    func trash(_ node: DiskNode) {
        guard !node.isSynthetic else { return }
        let report = Remover.remove([node.path], mode: .trash, sizes: [node.path: node.size])
        guard report.removed.contains(node.path) else {
            let alert = NSAlert()
            alert.messageText = "Couldn't move “\(node.name)” to the Trash"
            alert.informativeText = report.failures.first?.reason ?? "The item is protected."
            alert.runModal()
            return
        }
        let wasCurrent = current
        node.removeFromParent()
        largeFiles.removeAll { $0.path == node.path || $0.path.hasPrefix(node.path + "/") }
        current = nil
        current = wasCurrent === node ? node.parent : wasCurrent
        HistoryStore.shared.record(.analyze, title: "Moved \(node.name) to Trash", bytes: report.freedBytes, items: 1,
                                   details: [Paths.abbreviate(node.path)])
    }

    func trash(_ file: LargeFile) {
        let report = Remover.remove([file.path], mode: .trash, sizes: [file.path: file.size])
        if report.removed.contains(file.path) {
            largeFiles.removeAll { $0.path == file.path }
            HistoryStore.shared.record(.analyze, title: "Moved \(file.name) to Trash", bytes: report.freedBytes, items: 1,
                                       details: [Paths.abbreviate(file.path)])
            if let root { removeNode(path: file.path, from: root) }
        }
    }

    private func removeNode(path: String, from node: DiskNode) {
        if let match = node.children.first(where: { $0.path == path }) { match.removeFromParent(); return }
        if let next = node.children.first(where: { path.hasPrefix($0.path + "/") }) { removeNode(path: path, from: next) }
    }
}
