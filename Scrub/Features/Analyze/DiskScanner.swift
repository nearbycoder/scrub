import Foundation
import CoreGraphics

/// A folder or large file in a Space Lens tree. Nodes only store their own name; the full path is
/// derived from the parent chain, which keeps whole-disk trees compact.
final class DiskNode: Identifiable, Hashable {
    let name: String
    let isDirectory: Bool
    weak var parent: DiskNode?
    /// Set on the root only.
    var rootPath: String?
    var children: [DiskNode] = []
    var size: Int64 = 0
    var fileCount = 0
    /// Bytes and count of files directly inside this folder.
    var ownSize: Int64 = 0
    var ownFiles = 0
    var looseFileSize: Int64 = 0
    var looseFileCount = 0
    /// Deeper levels were measured but not kept; opening the folder walks it again.
    var isTruncated = false
    var isUnreadable = false
    var needsFullDiskAccess = false
    var isSynthetic = false
    var modified: Date?

    var id: ObjectIdentifier { ObjectIdentifier(self) }

    init(name: String, isDirectory: Bool) {
        self.name = name
        self.isDirectory = isDirectory
    }

    static func == (l: DiskNode, r: DiskNode) -> Bool { l === r }
    func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }

    lazy var path: String = {
        if let parent { return parent.path + "/" + name }
        return rootPath ?? "/" + name
    }()

    /// Bundles Finder shows as a single item, like apps and packages.
    var isPackage: Bool {
        guard isDirectory else { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        return ["app", "bundle", "framework", "plugin", "appex", "pkg", "photoslibrary", "musiclibrary", "xcarchive"].contains(ext)
    }

    /// The name to show. Simulator devices are folders named by UUID, so they're shown by the
    /// device name and OS version Xcode gave them instead.
    lazy var title: String = {
        // Finder hides the extension of apps.
        if isDirectory && name.hasSuffix(".app") { return String(name.dropLast(4)) }
        guard isDirectory, name.count == 36, parent?.name == "Devices", parent?.parent?.name == "CoreSimulator",
              let plist = NSDictionary(contentsOfFile: path + "/device.plist"),
              let device = plist["name"] as? String else { return name }
        // "com.apple.CoreSimulator.SimRuntime.iOS-26-1" → "iOS 26.1"
        guard let runtime = (plist["runtime"] as? String)?.split(separator: ".").last else { return device }
        let parts = runtime.split(separator: "-")
        guard let os = parts.first else { return device }
        return "\(device) (\(os) \(parts.dropFirst().joined(separator: ".")))"
    }()

    /// Children sorted by size, plus one tile for files too small to show individually.
    var displayChildren: [DiskNode] {
        if let cachedDisplay { return cachedDisplay }
        var list = children.sorted { $0.size > $1.size }
        if looseFileSize > 0 {
            let other = DiskNode(name: looseFileCount == 1 ? "1 smaller file" : "\(looseFileCount.formatted()) smaller files", isDirectory: false)
            other.size = looseFileSize
            other.isSynthetic = true
            other.parent = self
            list.append(other)
        }
        cachedDisplay = list
        return list
    }
    private var cachedDisplay: [DiskNode]?
    func invalidateDisplay() { cachedDisplay = nil }

    var ancestors: [DiskNode] {
        var chain: [DiskNode] = []
        var node: DiskNode? = self
        while let n = node { chain.insert(n, at: 0); node = n.parent }
        return chain
    }

    var depth: Int { var d = 0; var n = parent; while let p = n { d += 1; n = p.parent }; return d }

    /// Rolls sizes up the tree after a parallel walk. Iterative, so deep trees can't overflow a thread stack.
    func aggregate() {
        var order: [DiskNode] = []
        var stack: [DiskNode] = [self]
        while let n = stack.popLast() {
            order.append(n)
            for c in n.children where c.isDirectory { stack.append(c) }
        }
        for n in order.reversed() where n.isDirectory {
            var size = n.ownSize, files = n.ownFiles
            for c in n.children where c.isDirectory { size += c.size; files += c.fileCount }
            n.size = size
            n.fileCount = files
        }
    }

    /// Drops children below `depth` to keep memory bounded; those folders are re-walked when opened.
    func prune(below depth: Int) {
        var stack: [(DiskNode, Int)] = [(self, 0)]
        while let (n, d) = stack.popLast() {
            if d >= depth {
                if n.children.contains(where: \.isDirectory) {
                    n.children = []
                    n.looseFileSize = n.size
                    n.isTruncated = true
                }
                continue
            }
            for c in n.children where c.isDirectory { stack.append((c, d + 1)) }
        }
    }

    func removeFromParent() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        var node: DiskNode? = parent
        while let n = node {
            n.size -= size
            n.fileCount -= fileCount
            n.invalidateDisplay()
            node = n.parent
        }
    }
}

struct LargeFile: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let size: Int64
    let modified: Date
    var name: String { (path as NSString).lastPathComponent }
    var folder: String { Paths.abbreviate((path as NSString).deletingLastPathComponent) }
    var isStale: Bool { modified < Date().addingTimeInterval(-365 * 86_400) }
}

/// Squarified treemap layout (Bruls, Huizing & van Wijk).
enum Treemap {
    struct Tile { let node: DiskNode; let rect: CGRect }

    static func layout(_ nodes: [DiskNode], in rect: CGRect) -> [Tile] {
        let items = nodes.filter { $0.size > 0 }
        let total = items.reduce(0.0) { $0 + Double($1.size) }
        guard total > 0, rect.width > 1, rect.height > 1 else { return [] }
        let scale = Double(rect.width * rect.height) / total
        var remaining = items.map { (node: $0, area: Double($0.size) * scale) }[...]
        var tiles: [Tile] = []
        tiles.reserveCapacity(items.count)
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
