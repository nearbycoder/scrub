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
    private(set) var current: DiskNode?
    var largeFiles: [LargeFile] = []
    var isScanning = false
    var isRefreshingFolder = false
    var scannedFiles = 0
    var scannedBytes: Int64 = 0
    var scope: Scope?
    var lastScan: Date?
    var scanDuration: TimeInterval = 0
    private var backStack: [DiskNode] = []
    private var forwardStack: [DiskNode] = []
    private var progress = DiskWalker.Progress()

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    var scopes: [Scope] {
        var list = [
            Scope(path: Paths.home, title: "Home", symbol: "house"),
            Scope(path: Paths.isDirectory("/System/Volumes/Data") ? "/System/Volumes/Data" : "/", title: "Macintosh HD", symbol: "internaldrive"),
            Scope(path: "/Applications", title: "Applications", symbol: "square.grid.2x2"),
            Scope(path: Paths.home + "/Library", title: "Library", symbol: "building.columns"),
        ]
        let keys: [URLResourceKey] = [.volumeNameKey]
        for url in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        where url.path.hasPrefix("/Volumes/") {
            let name = (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? url.lastPathComponent
            list.append(Scope(path: url.path, title: name, symbol: "externaldrive"))
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
        backStack = []
        forwardStack = []
        largeFiles = []
        let progress = DiskWalker.Progress()
        self.progress = progress
        let started = Date()

        Task { @MainActor [weak self] in
            while let self, self.isScanning, !progress.isCancelled {
                self.scannedFiles = progress.files
                self.scannedBytes = progress.bytes
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            let skip: ((String) -> Bool)? = SystemAccess.hasFullDiskAccess ? nil : { SystemAccess.isPrivacyProtected($0) }
            let result = DiskWalker.tree(scope.path, skip: skip, progress: progress)
            guard !progress.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                if scope.path == "/System/Volumes/Data" {
                    let renamed = DiskNode(name: "Macintosh HD", isDirectory: true)
                    renamed.rootPath = scope.path
                    renamed.size = result.root.size
                    renamed.fileCount = result.root.fileCount
                    renamed.children = result.root.children
                    renamed.looseFileSize = result.root.looseFileSize
                    renamed.looseFileCount = result.root.looseFileCount
                    result.root.children.forEach { $0.parent = renamed }
                    self.root = renamed
                } else {
                    self.root = result.root
                }
                self.current = self.root
                self.largeFiles = result.large
                self.scannedFiles = progress.files
                self.scannedBytes = progress.bytes
                self.scanDuration = Date().timeIntervalSince(started)
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
        scan(Scope(path: url.path, title: url.lastPathComponent, symbol: "folder"))
    }

    func cancel() {
        progress.cancel()
        isScanning = false
    }

    // MARK: Navigation

    func open(_ node: DiskNode) {
        guard node.isDirectory, !node.isSynthetic, !node.isUnreadable, node !== current else { return }
        if let current { backStack.append(current) }
        forwardStack = []
        if node.isTruncated { refresh(node) }
        current = node
    }

    func show(_ node: DiskNode) {
        guard node !== current else { return }
        if let current { backStack.append(current) }
        forwardStack = []
        current = node
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        if let current { forwardStack.append(current) }
        current = previous
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let current { backStack.append(current) }
        current = next
    }

    func goUp() {
        if let parent = current?.parent { show(parent) }
    }

    /// Re-walks a folder whose deeper levels were summarised, and grafts the result in place.
    private func refresh(_ node: DiskNode) {
        isRefreshingFolder = true
        let path = node.path
        Task.detached(priority: .userInitiated) { [weak self] in
            let skip: ((String) -> Bool)? = SystemAccess.hasFullDiskAccess ? nil : { SystemAccess.isPrivacyProtected($0) }
            let result = DiskWalker.tree(path, skip: skip, progress: DiskWalker.Progress())
            await MainActor.run {
                node.children = result.root.children
                node.children.forEach { $0.parent = node }
                node.looseFileSize = result.root.looseFileSize
                node.looseFileCount = result.root.looseFileCount
                node.isTruncated = false
                node.invalidateDisplay()
                self?.isRefreshingFolder = false
                if let self, self.current === node { self.current = nil; self.current = node }
            }
        }
    }

    // MARK: Removal

    func trash(_ node: DiskNode) {
        guard !node.isSynthetic else { return }
        let path = node.path
        let report = Remover.remove([path], mode: .trash, sizes: [path: node.size])
        guard report.removed.contains(path) else {
            let alert = NSAlert()
            alert.messageText = "“\(node.name)” couldn't be moved to the Trash"
            alert.informativeText = report.failures.first?.reason ?? "The item is protected."
            alert.runModal()
            return
        }
        let wasCurrent = current
        node.removeFromParent()
        largeFiles.removeAll { $0.path == path || $0.path.hasPrefix(path + "/") }
        current = nil
        current = wasCurrent === node ? node.parent : wasCurrent
        HistoryStore.shared.record(.analyze, title: "Moved \(node.name) to the Trash", bytes: report.freedBytes, items: 1,
                                   details: [Paths.abbreviate(path)])
    }

    func trash(_ file: LargeFile) {
        let report = Remover.remove([file.path], mode: .trash, sizes: [file.path: file.size])
        guard report.removed.contains(file.path) else { return }
        largeFiles.removeAll { $0.path == file.path }
        HistoryStore.shared.record(.analyze, title: "Moved \(file.name) to the Trash", bytes: report.freedBytes, items: 1,
                                   details: [Paths.abbreviate(file.path)])
        if let root, let node = find(file.path, in: root) {
            node.removeFromParent()
            let c = current; current = nil; current = c
        }
    }

    private func find(_ path: String, in node: DiskNode) -> DiskNode? {
        var n = node
        while true {
            guard let next = n.children.first(where: { path == $0.path || path.hasPrefix($0.path + "/") }) else { return nil }
            if next.path == path { return next }
            n = next
        }
    }
}
