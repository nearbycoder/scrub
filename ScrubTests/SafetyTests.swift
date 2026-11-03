import XCTest
@testable import Scrub

final class PathGuardTests: XCTestCase {
    func testDeniesSystemAndTopLevelFolders() {
        let h = Paths.home
        for path in ["/", "/System", "/System/Library/Caches", "/usr/bin", "/Applications", "/Library",
                     h, h + "/Library", h + "/Documents", h + "/Desktop", h + "/Library/Caches", h + "/Desktop/../Library"] {
            XCTAssertFalse(PathGuard.isAllowed(path), "\(path) should be protected")
        }
    }

    func testAllowsChildrenOfCacheFolders() {
        XCTAssertTrue(PathGuard.isAllowed(Paths.home + "/Library/Caches/com.example.app"))
        XCTAssertTrue(PathGuard.isAllowed("/Applications/Example.app"))
    }

    func testRespectsUserProtectedPaths() {
        let path = Paths.home + "/Library/Caches/com.example.keep"
        XCTAssertEqual(PathGuard.check(path + "/inner", protected: ["~/Library/Caches/com.example.keep"]), .denied("Protected in Settings"))
    }
}

final class DiskWalkerTests: XCTestCase {
    private var base: String!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("scrub-tests-\(UUID().uuidString)").path
        let fm = FileManager.default
        try fm.createDirectory(atPath: base + "/a/b/c", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: base + "/empty", withIntermediateDirectories: true)
        fm.createFile(atPath: base + "/a/one", contents: Data(repeating: 1, count: 100_000))
        fm.createFile(atPath: base + "/a/b/two", contents: Data(repeating: 2, count: 300_000))
        fm.createFile(atPath: base + "/a/b/c/three", contents: Data(repeating: 3, count: 50_000))
        try fm.linkItem(atPath: base + "/a/b/two", toPath: base + "/a/hardlink")
        try fm.createSymbolicLink(atPath: base + "/a/link", withDestinationPath: "/System")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: base)
    }

    func testMeasureMatchesDuAndCountsHardlinksOnce() {
        let result = DiskWalker.measure([base + "/a", base + "/empty"])
        let a = result[base + "/a"]!
        XCTAssertEqual(a.files, 4, "one, two, three and the symlink; the hard link is counted once")
        XCTAssertGreaterThanOrEqual(a.size, 450_000)
        XCTAssertLessThan(a.size, 600_000, "symlinks must not be followed")
        XCTAssertEqual(result[base + "/empty"]?.size, 0)
        XCTAssertNotNil(a.newest)
    }

    func testTreeAggregatesSizes() {
        let (root, _) = DiskWalker.tree(base, fileNodeThreshold: 200_000, progress: DiskWalker.Progress())
        let a = root.children.first { $0.name == "a" }!
        let b = a.children.first { $0.name == "b" }!
        XCTAssertEqual(root.size, a.size + (root.children.first { $0.name == "empty" }?.size ?? 0))
        // "two" and "hardlink" share an inode; whichever the parallel walk reaches first is counted.
        let fileNodes = (a.children + b.children).filter { !$0.isDirectory }.map(\.name)
        XCTAssertEqual(fileNodes.filter { $0 == "two" || $0 == "hardlink" }.count, 1, "large files become nodes, hard links once")
        XCTAssertEqual(b.path, base + "/a/b")
        XCTAssertGreaterThan(a.size, b.size)
    }

    func testPruneKeepsSizes() {
        let (root, _) = DiskWalker.tree(base, retainDepth: 1, progress: DiskWalker.Progress())
        let a = root.children.first { $0.name == "a" }!
        XCTAssertTrue(a.isTruncated)
        XCTAssertTrue(a.children.isEmpty)
        XCTAssertGreaterThan(a.size, 400_000)
    }
}

final class RemoverTests: XCTestCase {
    private var base: String!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("scrub-tests-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: base + "/a/b", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: base + "/a/b/file", contents: Data(count: 200_000))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: base)
    }

    func testMeasuresAndDeletesPermanently() {
        XCTAssertGreaterThanOrEqual(FileSizer.allocatedSize(atPath: base), 200_000)
        let report = Remover.remove([base + "/a"], mode: .permanent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: base + "/a"))
        XCTAssertGreaterThan(report.freedBytes, 190_000)
    }

    func testRefusesProtectedLocations() {
        let report = Remover.remove([Paths.home + "/Library"], mode: .permanent)
        XCTAssertTrue(report.removed.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: Paths.home + "/Library"))
    }
}

final class TreemapTests: XCTestCase {
    func testLayoutFillsRectProportionally() {
        let nodes = [400, 300, 200, 100].map { size -> DiskNode in
            let n = DiskNode(name: "\(size)", isDirectory: false)
            n.size = Int64(size)
            return n
        }
        let tiles = Treemap.layout(nodes, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(tiles.count, 4)
        XCTAssertEqual(tiles.reduce(0) { $0 + $1.rect.width * $1.rect.height }, 10_000, accuracy: 1)
        let biggest = tiles.first { $0.node.size == 400 }!.rect
        XCTAssertEqual(biggest.width * biggest.height, 4_000, accuracy: 1)
    }
}

final class OrphanFinderTests: XCTestCase {
    func testBundleIdentifierHeuristics() {
        XCTAssertTrue(OrphanFinder.isBundleIdentifier("com.example.app"))
        XCTAssertFalse(OrphanFinder.isBundleIdentifier("Google"))
        XCTAssertFalse(OrphanFinder.isBundleIdentifier("com.example"))
        XCTAssertEqual(OrphanFinder.vendor("com.Example.App.helper"), "com.example")
    }
}

final class UpdaterTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(Updater.isNewer("1.2.0", than: "1.1.0"))
        XCTAssertTrue(Updater.isNewer("1.10", than: "1.9.9"))
        XCTAssertTrue(Updater.isNewer("2", than: "1.99.99"))
        XCTAssertFalse(Updater.isNewer("1.1.0", than: "1.1"))
        XCTAssertFalse(Updater.isNewer("1.0.9", than: "1.1.0"))
    }

    func testRunningAppTeamMatchesItself() {
        let team = Updater.teamIdentifier(of: Bundle.main.bundleURL)
        XCTAssertEqual(team, Updater.teamIdentifier(of: Bundle.main.bundleURL))
    }
}

final class ProjectKindTests: XCTestCase {
    func testDetection() {
        XCTAssertEqual(ProjectKind.detect("/x", entries: ["Cargo.toml", "src"]), .rust)
        XCTAssertEqual(ProjectKind.detect("/x", entries: ["package.json", "node_modules"]), .node)
        XCTAssertEqual(ProjectKind.detect("/x", entries: ["App.xcodeproj", "package.json"]), .xcode)
        XCTAssertEqual(ProjectKind.detect("/x", entries: ["pyproject.toml"]), .python)
        XCTAssertEqual(ProjectKind.detect("/x", entries: ["README.md"]), .other)
    }
}
