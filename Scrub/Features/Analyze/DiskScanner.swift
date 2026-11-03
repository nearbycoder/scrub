import Foundation

final class DiskNode: Identifiable, Hashable {
    let path: String
    let name: String
    let isDirectory: Bool
    var size: Int64 = 0
    var fileCount = 0
    var looseFileSize: Int64 = 0
    var looseFileCount = 0
    var children: [DiskNode] = []
    weak var parent: DiskNode?
    /// Deeper levels were rolled up into this node and need a fresh scan to explore.
    var isTruncated = false
    var isUnreadable = false
    var needsFullDiskAccess = false
    var modified: Date?

    var id: String { path }

    init(path: String, name: String? = nil, isDirectory: Bool) {
        self.path = path
        self.name = name ?? (path == "/" ? "Macintosh HD" : (path as NSString).lastPathComponent)
        self.isDirectory = isDirectory
    }

    static func == (l: DiskNode, r: DiskNode) -> Bool { l === r }
    func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }

    /// Children plus a synthetic tile representing files too small to list individually.
    var displayChildren: [DiskNode] {
        var list = children.sorted { $0.size > $1.size }
        if looseFileSize > 0 {
            let other = DiskNode(path: path + "/\u{0}files", name: "\(looseFileCount) smaller files", isDirectory: false)
            other.size = looseFileSize
            other.parent = self
            list.append(other)
        }
        return list
    }

    var isSynthetic: Bool { path.hasSuffix("/\u{0}files") }

    var ancestors: [DiskNode] {
        var chain: [DiskNode] = []
        var node: DiskNode? = self
        while let n = node { chain.insert(n, at: 0); node = n.parent }
        return chain
    }

    func removeFromParent() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        var node: DiskNode? = parent
        while let n = node { n.size -= size; n.fileCount -= fileCount; node = n.parent }
    }
}

struct LargeFile: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let size: Int64
    let accessed: Date
    let modified: Date
    var name: String { (path as NSString).lastPathComponent }
    var isUnused: Bool { max(accessed, modified) < Date().addingTimeInterval(-365 * 86_400) }
}

struct DiskScanResult {
    let root: DiskNode
    let largeFiles: [LargeFile]
    let scannedFiles: Int
}

enum DiskScanner {
    static let maxDepth = 6
    static let fileNodeThreshold: Int64 = 8 * 1024 * 1024
    static let largeFileThreshold: Int64 = 100 * 1024 * 1024

    static func scan(_ rootPath: String, progress: (Int, Int64) -> Void, isCancelled: () -> Bool) -> DiskScanResult {
        // Without Full Disk Access, reading app data folders triggers privacy prompts; skip them instead.
        let fullDiskAccess = SystemAccess.hasFullDiskAccess
        let skip: ((String) -> Bool)? = fullDiskAccess ? nil : { SystemAccess.isPrivacyProtected($0) }
        var stack: [DiskNode] = []
        var root: DiskNode?
        var large: [LargeFile] = []
        var seenInodes = Set<UInt64>()
        var count = 0
        var total: Int64 = 0

        FileSizer.walkDetailed(rootPath, skip: skip) { entry, st, level, cPath, _ in
            count += 1
            if count % 4000 == 0 {
                progress(count, total)
                if isCancelled() { return false }
            }
            switch entry {
            case .directoryPre, .skipped:
                if level <= maxDepth {
                    let node = DiskNode(path: String(cString: cPath), isDirectory: true)
                    if entry == .skipped { node.isUnreadable = true; node.needsFullDiskAccess = true }
                    node.modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
                    if let top = stack.last { node.parent = top; top.children.append(node) } else { root = node }
                    stack.append(node)
                } else {
                    stack.last?.isTruncated = true
                }
            case .directoryPost:
                if level <= maxDepth, let node = stack.popLast(), let parent = stack.last {
                    parent.size += node.size
                    parent.fileCount += node.fileCount
                }
            case .unreadable:
                let path = String(cString: cPath)
                if let top = stack.last, top.path == path {
                    top.isUnreadable = true
                } else if level <= maxDepth, level > 0, let top = stack.last {
                    let node = DiskNode(path: path, isDirectory: true)
                    node.isUnreadable = true
                    node.parent = top
                    top.children.append(node)
                }
            case .file:
                if st.st_nlink > 1, !seenInodes.insert(st.st_ino).inserted { return true }
                let size = Int64(st.st_blocks) * 512
                total += size
                guard let top = stack.last else {
                    // Scanning a single file.
                    let node = DiskNode(path: String(cString: cPath), isDirectory: false)
                    node.size = size
                    root = node
                    return true
                }
                top.size += size
                top.fileCount += 1
                if level - 1 <= maxDepth && level - 1 == stack.count - 1 && size >= fileNodeThreshold {
                    let node = DiskNode(path: String(cString: cPath), isDirectory: false)
                    node.size = size
                    node.fileCount = 1
                    node.parent = top
                    node.modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
                    top.children.append(node)
                } else if level - 1 == stack.count - 1 {
                    top.looseFileSize += size
                    top.looseFileCount += 1
                }
                if size >= largeFileThreshold {
                    let lf = LargeFile(path: String(cString: cPath), size: size,
                                       accessed: Date(timeIntervalSince1970: TimeInterval(st.st_atimespec.tv_sec)),
                                       modified: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)))
                    large.append(lf)
                    if large.count > 400 {
                        large.sort { $0.size > $1.size }
                        large.removeLast(large.count - 200)
                    }
                }
            }
            return true
        }
        // Directories truncated below maxDepth still hold the sizes of everything under them;
        // fold their deeper usage into "loose" space so the treemap stays accurate.
        if let root { fixLooseSizes(root) }
        progress(count, total)
        let r = root ?? DiskNode(path: rootPath, isDirectory: true)
        return DiskScanResult(root: r, largeFiles: Array(large.sorted { $0.size > $1.size }.prefix(200)), scannedFiles: count)
    }

    private static func fixLooseSizes(_ node: DiskNode) {
        guard node.isDirectory else { return }
        for child in node.children { fixLooseSizes(child) }
        let accounted = node.children.reduce(0) { $0 + $1.size }
        node.looseFileSize = max(0, node.size - accounted)
        if node.looseFileSize == 0 { node.looseFileCount = 0 }
        if node.looseFileCount == 0 && node.looseFileSize > 0 { node.looseFileCount = max(1, node.fileCount - node.children.reduce(0) { $0 + $1.fileCount }) }
    }
}

/// Squarified treemap layout (Bruls, Huizing & van Wijk).
enum Treemap {
    struct Tile { let node: DiskNode; let rect: CGRect }

    static func layout(_ nodes: [DiskNode], in rect: CGRect) -> [Tile] {
        let items = nodes.filter { $0.size > 0 }
        let total = items.reduce(0.0) { $0 + Double($1.size) }
        guard total > 0, rect.width > 1, rect.height > 1 else { return [] }
        let scale = Double(rect.width * rect.height) / total
        var remaining = items.map { (node: $0, area: Double($0.size) * scale) }
        var tiles: [Tile] = []
        var free = rect

        while !remaining.isEmpty {
            let side = Double(min(free.width, free.height))
            var row: [(node: DiskNode, area: Double)] = []
            var best = Double.infinity
            while let next = remaining.first {
                let candidate = row + [next]
                let w = worst(candidate.map(\.area), side: side)
                if w <= best || row.isEmpty {
                    best = w
                    row = candidate
                    remaining.removeFirst()
                } else { break }
            }
            let rowArea = row.reduce(0) { $0 + $1.area }
            if free.width >= free.height {
                let width = CGFloat(rowArea / Double(free.height))
                var y = free.minY
                for item in row {
                    let h = CGFloat(item.area) / width
                    tiles.append(Tile(node: item.node, rect: CGRect(x: free.minX, y: y, width: width, height: h)))
                    y += h
                }
                free = CGRect(x: free.minX + width, y: free.minY, width: max(0, free.width - width), height: free.height)
            } else {
                let height = CGFloat(rowArea / Double(free.width))
                var x = free.minX
                for item in row {
                    let w = CGFloat(item.area) / height
                    tiles.append(Tile(node: item.node, rect: CGRect(x: x, y: free.minY, width: w, height: height)))
                    x += w
                }
                free = CGRect(x: free.minX, y: free.minY + height, width: free.width, height: max(0, free.height - height))
            }
        }
        return tiles
    }

    private static func worst(_ areas: [Double], side: Double) -> Double {
        let sum = areas.reduce(0, +)
        guard let maxA = areas.max(), let minA = areas.min(), sum > 0, side > 0 else { return .infinity }
        let s2 = side * side, sum2 = sum * sum
        return max(s2 * maxA / sum2, sum2 / (s2 * minA))
    }
}
