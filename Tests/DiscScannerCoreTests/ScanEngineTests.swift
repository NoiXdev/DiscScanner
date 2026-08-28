import Testing
import Foundation
@testable import DiscScannerCore

struct ScanEngineTests {
    /// root/
    ///   a.bin            100 KiB
    ///   sub1/b.bin       200 KiB
    ///   sub1/c.bin        50 KiB
    ///   sub1/nested/d.bin 24 KiB
    ///   link -> sub1     (symlink, must not be followed)
    /// Sizes are mostly block-aligned; assertions allow one block (4096 bytes)
    /// of slack for APFS allocation rounding.
    private func makeFixture() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("scan-fixture-\(UUID().uuidString)")
        try fm.createDirectory(
            at: root.appendingPathComponent("sub1/nested"),
            withIntermediateDirectories: true
        )
        func write(_ relativePath: String, bytes: Int) throws {
            try Data(repeating: 1, count: bytes)
                .write(to: root.appendingPathComponent(relativePath))
        }
        try write("a.bin", bytes: 102_400)
        try write("sub1/b.bin", bytes: 204_800)
        try write("sub1/c.bin", bytes: 51_200)
        try write("sub1/nested/d.bin", bytes: 24_576)
        try fm.createSymbolicLink(
            at: root.appendingPathComponent("link"),
            withDestinationURL: root.appendingPathComponent("sub1")
        )
        return root
    }

    @Test func aggregatesSizesBottomUpAndSkipsSymlinks() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = ScanState()
        let tree = DiskScanner.performScan(url: root, state: state)

        let sub1 = tree.find(path: root.appendingPathComponent("sub1").path)
        let expectedSub1: Int64 = 204_800 + 51_200 + 24_576
        #expect(sub1?.allocatedSize ?? 0 >= expectedSub1)
        #expect(sub1?.allocatedSize ?? 0 <= expectedSub1 + 4_096)

        let link = tree.find(path: root.appendingPathComponent("link").path)
        #expect(link != nil)
        #expect(link?.isDirectory == false)
        #expect(link?.children.isEmpty == true)

        let filesTotal: Int64 = 102_400 + 204_800 + 51_200 + 24_576
        #expect(tree.allocatedSize >= filesTotal)
        // small slack for the symlink inode itself
        #expect(tree.allocatedSize <= filesTotal + 8_192)

        let sizes = tree.children.map(\.allocatedSize)
        #expect(sizes == sizes.sorted(by: >))

        let progress = state.progressSnapshot()
        #expect(progress.filesScanned == 5) // 4 files + 1 symlink
        #expect(progress.directoriesScanned == 3) // root, sub1, nested
    }

    @Test func marksUnreadableDirectoriesAndContinues() throws {
        let fm = FileManager.default
        let root = try makeFixture()
        let lockedDir = root.appendingPathComponent("locked")
        try fm.createDirectory(at: lockedDir, withIntermediateDirectories: false)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedDir.path)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedDir.path)
            try? fm.removeItem(at: root)
        }
        let state = ScanState()
        let tree = DiskScanner.performScan(url: root, state: state)

        #expect(tree.find(path: lockedDir.path)?.isAccessDenied == true)
        #expect(state.progressSnapshot().accessDeniedCount == 1)
        // scan continued past the locked dir
        #expect(tree.find(path: root.appendingPathComponent("a.bin").path) != nil)
    }

    @Test func cancelledScanReturnsPartialTree() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = ScanState()
        state.cancel()
        let tree = DiskScanner.performScan(url: root, state: state)
        #expect(tree.children.isEmpty)
    }
}
