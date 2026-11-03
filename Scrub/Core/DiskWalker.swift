import Foundation
import os

/// Parallel, hardlink-aware directory walker built on `getattrlistbulk(2)`.
///
/// `getattrlistbulk` returns names, types, sizes and dates for a whole batch of directory entries in a
/// single system call, which is several times cheaper than `fts`/`stat` per file. Directories are fanned
/// out across a pool of worker threads, so large trees are measured using every core.
enum DiskWalker {
    struct Measurement {
        var size: Int64 = 0
        var files = 0
        /// Newest modification date found anywhere inside the item.
        var newest: Date?
    }

    final class Progress: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: (files: 0, bytes: Int64(0)))
        private let cancelled = OSAllocatedUnfairLock(initialState: false)
        var files: Int { lock.withLock { $0.files } }
        var bytes: Int64 { lock.withLock { $0.bytes } }
        var isCancelled: Bool { cancelled.withLock { $0 } }
        func cancel() { cancelled.withLock { $0 = true } }
        func add(files: Int, bytes: Int64) { lock.withLock { $0.files += files; $0.bytes += bytes } }
    }

    /// One directory entry as returned by the kernel.
    struct Entry {
        enum Kind { case file, directory, symlink, other }
        var name: String
        var kind: Kind
        var allocated: Int64
        var modified: Int
        var fileID: UInt64
        var linkCount: UInt32
        var device: Int32
    }

    static var workerCount: Int { max(4, min(16, ProcessInfo.processInfo.activeProcessorCount)) }

    // MARK: - Measuring many items

    /// Measures every path in parallel. Paths may be files or directories; symlinks are never followed.
    static func measure(_ paths: [String], skip: ((String) -> Bool)? = nil, progress: Progress? = nil) -> [String: Measurement] {
        guard !paths.isEmpty else { return [:] }
        let unique = Array(Set(paths))
        var results = [Measurement](repeating: Measurement(), count: unique.count)
        let resultLock = OSAllocatedUnfairLock()
        let links = HardlinkSet()

        var seeds: [(String, Int)] = []
        for (index, path) in unique.enumerated() {
            if skip?(path) == true { continue }
            var st = stat()
            guard lstat(path, &st) == 0 else { continue }
            if (st.st_mode & S_IFMT) == S_IFDIR {
                seeds.append((path, index))
                results[index].newest = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
            } else {
                results[index].size = Int64(st.st_blocks) * 512
                results[index].files = 1
                results[index].newest = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
            }
        }

        let rootDevices = Dictionary(uniqueKeysWithValues: seeds.map { ($0.1, deviceID($0.0)) })
        let pool = WorkPool<(path: String, root: Int)>(seeds.map { (path: $0.0, root: $0.1) })
        pool.run(workers: workerCount) { item, push, local in
            if progress?.isCancelled == true { return }
            var size: Int64 = 0, files = 0, newest = 0
            let device = rootDevices[item.root] ?? -1
            readDirectory(item.path, buffer: &local.buffer) { entry in
                switch entry.kind {
                case .directory:
                    let child = item.path + "/" + entry.name
                    if entry.device == device, skip?(child) != true { push((child, item.root)) }
                case .file, .symlink:
                    if entry.linkCount > 1 && !links.insert(entry.fileID) { return }
                    size += entry.allocated
                    files += 1
                    newest = max(newest, entry.modified)
                case .other:
                    break
                }
            }
            progress?.add(files: files, bytes: size)
            resultLock.withLock {
                results[item.root].size += size
                results[item.root].files += files
                if newest > 0 {
                    let d = Date(timeIntervalSince1970: TimeInterval(newest))
                    if d > (results[item.root].newest ?? .distantPast) { results[item.root].newest = d }
                }
            }
        }

        var out: [String: Measurement] = [:]
        for (index, path) in unique.enumerated() { out[path] = results[index] }
        return out
    }

    static func size(of path: String) -> Int64 { measure([path])[path]?.size ?? 0 }

    // MARK: - Building a tree (Space Lens)

    /// Walks `root` in parallel and returns a directory tree. Files at least `fileNodeThreshold` bytes become
    /// their own nodes; smaller ones are summed into their folder. Directories deeper than `retainDepth`
    /// keep their size but drop their children, and are re-walked on demand.
    static func tree(_ root: String, retainDepth: Int = 10, fileNodeThreshold: Int64 = 16 << 20,
                     largeFileThreshold: Int64 = 100 << 20, skip: ((String) -> Bool)? = nil,
                     progress: Progress) -> (root: DiskNode, large: [LargeFile]) {
        let rootNode = DiskNode(name: root == "/" ? "Macintosh HD" : (root as NSString).lastPathComponent, isDirectory: true)
        rootNode.rootPath = root
        rootNode.modified = Paths.modificationDate(root)
        let device = deviceID(root)
        let links = HardlinkSet()
        let largeLock = OSAllocatedUnfairLock(initialState: [LargeFile]())

        let pool = WorkPool<(path: String, node: DiskNode)>([(path: root, node: rootNode)])
        pool.run(workers: workerCount) { item, push, local in
            if progress.isCancelled { return }
            let node = item.node
            var looseSize: Int64 = 0, looseCount = 0, files = 0, total: Int64 = 0
            var children: [DiskNode] = []
            var large: [LargeFile] = []
            let ok = readDirectory(item.path, buffer: &local.buffer) { entry in
                switch entry.kind {
                case .directory:
                    let childPath = item.path + "/" + entry.name
                    let child = DiskNode(name: entry.name, isDirectory: true)
                    child.parent = node
                    child.modified = Date(timeIntervalSince1970: TimeInterval(entry.modified))
                    children.append(child)
                    if entry.device != device {
                        child.isUnreadable = true
                    } else if skip?(childPath) == true {
                        child.isUnreadable = true
                        child.needsFullDiskAccess = true
                    } else {
                        push((childPath, child))
                    }
                case .file, .symlink:
                    if entry.linkCount > 1 && !links.insert(entry.fileID) { return }
                    files += 1
                    total += entry.allocated
                    if entry.allocated >= fileNodeThreshold {
                        let f = DiskNode(name: entry.name, isDirectory: false)
                        f.size = entry.allocated
                        f.fileCount = 1
                        f.parent = node
                        f.modified = Date(timeIntervalSince1970: TimeInterval(entry.modified))
                        children.append(f)
                    } else {
                        looseSize += entry.allocated
                        looseCount += 1
                    }
                    if entry.allocated >= largeFileThreshold {
                        large.append(LargeFile(path: item.path + "/" + entry.name, size: entry.allocated,
                                               modified: Date(timeIntervalSince1970: TimeInterval(entry.modified))))
                    }
                case .other:
                    break
                }
            }
            // Only this worker touches `node` while it is being read.
            node.children = children
            node.looseFileSize = looseSize
            node.looseFileCount = looseCount
            node.ownSize = total
            node.ownFiles = files
            if !ok { node.isUnreadable = true }
            progress.add(files: files, bytes: total)
            if !large.isEmpty { largeLock.withLock { $0.append(contentsOf: large) } }
        }

        rootNode.aggregate()
        rootNode.prune(below: retainDepth)
        let large = largeLock.withLock { $0 }.sorted { $0.size > $1.size }
        return (rootNode, Array(large.prefix(300)))
    }

    // MARK: - getattrlistbulk

    /// Reads one directory, calling `body` for each entry. Returns false when the directory can't be opened.
    @discardableResult
    static func readDirectory(_ path: String, buffer: inout [UInt8], _ body: (Entry) -> Void) -> Bool {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var attrs = attrlist()
        attrs.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attrs.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_DEVID)
            | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_MODTIME) | attrgroup_t(ATTR_CMN_FILEID) | attrgroup_t(ATTR_CMN_ERROR)
        attrs.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)

        return buffer.withUnsafeMutableBytes { raw -> Bool in
            let base = raw.baseAddress!
            while true {
                let count = getattrlistbulk(fd, &attrs, base, raw.count, 0)
                if count <= 0 { return count == 0 }
                var entryPtr = base
                for _ in 0..<count {
                    let length = Int(entryPtr.loadUnaligned(as: UInt32.self))
                    defer { entryPtr += length }
                    var field = entryPtr + 4
                    let returned = field.loadUnaligned(as: attribute_set_t.self)
                    field += MemoryLayout<attribute_set_t>.size

                    var name = ""
                    if returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 {
                        let ref = field.loadUnaligned(as: attrreference_t.self)
                        name = String(cString: (field + Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
                        field += MemoryLayout<attrreference_t>.size
                    }
                    var device: Int32 = 0
                    if returned.commonattr & attrgroup_t(ATTR_CMN_DEVID) != 0 {
                        device = field.loadUnaligned(as: Int32.self)
                        field += 4
                    }
                    var type: UInt32 = 0
                    if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
                        type = field.loadUnaligned(as: UInt32.self)
                        field += 4
                    }
                    var modified = 0
                    if returned.commonattr & attrgroup_t(ATTR_CMN_MODTIME) != 0 {
                        modified = Int(field.loadUnaligned(as: timespec.self).tv_sec)
                        field += MemoryLayout<timespec>.size
                    }
                    var fileID: UInt64 = 0
                    if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 {
                        fileID = field.loadUnaligned(as: UInt64.self)
                        field += 8
                    }
                    if returned.commonattr & attrgroup_t(ATTR_CMN_ERROR) != 0 {
                        let error = field.loadUnaligned(as: UInt32.self)
                        field += 4
                        if error != 0 { continue }
                    }
                    var links: UInt32 = 1
                    var allocated: Int64 = 0
                    if returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 {
                        links = field.loadUnaligned(as: UInt32.self)
                        field += 4
                    }
                    if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
                        allocated = field.loadUnaligned(as: Int64.self)
                        field += 8
                    }
                    let kind: Entry.Kind
                    switch Int(type) {
                    case Int(VREG.rawValue): kind = .file
                    case Int(VDIR.rawValue): kind = .directory
                    case Int(VLNK.rawValue): kind = .symlink
                    default: kind = .other
                    }
                    body(Entry(name: name, kind: kind, allocated: allocated, modified: modified,
                               fileID: fileID, linkCount: links, device: device))
                }
            }
        }
    }

    static func deviceID(_ path: String) -> Int32 {
        var st = stat()
        return lstat(path, &st) == 0 ? st.st_dev : -1
    }
}

/// Thread-safe set of inode numbers used to count hard-linked files once.
final class HardlinkSet: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Set<UInt64>())
    func insert(_ id: UInt64) -> Bool { lock.withLock { $0.insert(id).inserted } }
}

/// A minimal work-stealing pool: workers pop items from a shared stack and may push more work.
final class WorkPool<Item>: @unchecked Sendable {
    final class Local { var buffer = [UInt8](repeating: 0, count: 128 * 1024) }

    private let condition = NSCondition()
    private var stack: [Item]
    private var pending: Int

    init(_ seeds: [Item]) {
        stack = seeds
        pending = seeds.count
    }

    func run(workers: Int, _ work: @escaping (Item, (Item) -> Void, Local) -> Void) {
        guard pending > 0 else { return }
        let group = DispatchGroup()
        for _ in 0..<workers {
            group.enter()
            let thread = Thread { [self] in
                let local = Local()
                var outbox: [Item] = []
                let push: (Item) -> Void = { outbox.append($0) }
                while let item = next() {
                    work(item, push, local)
                    finish(adding: outbox)
                    outbox.removeAll(keepingCapacity: true)
                }
                group.leave()
            }
            thread.stackSize = 1 << 20
            thread.qualityOfService = .userInitiated
            thread.start()
        }
        group.wait()
    }

    private func next() -> Item? {
        condition.lock()
        defer { condition.unlock() }
        while stack.isEmpty && pending > 0 { condition.wait() }
        return stack.popLast()
    }

    private func finish(adding items: [Item]) {
        condition.lock()
        stack.append(contentsOf: items)
        pending += items.count - 1
        if pending == 0 || !items.isEmpty { condition.broadcast() }
        condition.unlock()
    }
}
