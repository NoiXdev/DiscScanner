import Testing
import Foundation
@testable import DiscScannerCore

struct ScanStreamTests {
    /// 500 directories x 50 files x 4 KiB — large enough that a 10 ms
    /// snapshot interval fires several times before the scan completes.
    private func makeLargeFixture() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("scan-stream-\(UUID().uuidString)")
        for directoryIndex in 0..<500 {
            let dir = root.appendingPathComponent("dir\(directoryIndex)")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for fileIndex in 0..<50 {
                try Data(repeating: 1, count: 4_096)
                    .write(to: dir.appendingPathComponent("f\(fileIndex).bin"))
            }
        }
        return root
    }

    @Test func streamsSnapshotsAndProgressBeforeFinishing() async throws {
        let root = try makeLargeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        var sawSnapshotBeforeFinish = false
        var sawProgress = false
        var finishedTree: FileNode?

        let scanner = DiskScanner()
        for await event in scanner.scan(url: root, interval: 0.01) {
            switch event {
            case .snapshot:
                if finishedTree == nil { sawSnapshotBeforeFinish = true }
            case .progress(let progress):
                if progress.filesScanned > 0 { sawProgress = true }
            case .finished(let tree):
                finishedTree = tree
            }
        }

        #expect(sawSnapshotBeforeFinish)
        #expect(sawProgress)
        #expect(finishedTree?.children.count == 500)
        #expect(finishedTree?.allocatedSize == Int64(500 * 50 * 4_096))
    }
}
