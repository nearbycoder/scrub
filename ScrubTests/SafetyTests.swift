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
            let n = DiskNode(path: "/tmp/\(size)", isDirectory: false)
            n.size = Int64(size)
            return n
        }
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let tiles = Treemap.layout(nodes, in: rect)
        XCTAssertEqual(tiles.count, 4)
        let area = tiles.reduce(0) { $0 + $1.rect.width * $1.rect.height }
        XCTAssertEqual(area, 10_000, accuracy: 1)
        XCTAssertEqual(tiles.first { $0.node.size == 400 }!.rect.width * tiles.first { $0.node.size == 400 }!.rect.height, 4_000, accuracy: 1)
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
