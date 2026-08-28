import Testing
import Foundation
@testable import DiscScannerCore

struct ScanStreamTests {
    /// A chain of 300 nested directories (d/d/d/...), each containing one
    /// 4 KiB file. Parallel traversal cannot shortcut a chain — each
    /// directory is only discovered after its parent has been read — so this
    /// fixture stays measurably slower than a short snapshot interval even
    /// though it is tiny on disk and fast to create. Directory/file names
    /// are kept short (rather than index-suffixed) so 300 levels of nesting
    /// stay well under the OS path-length limit.
    private let chainDepth = 300

    private func makeChainFixture() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("scan-stream-\(UUID().uuidString)")
        var dir = root
        for _ in 0..<chainDepth {
            dir = dir.appendingPathComponent("d")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 4_096)
                .write(to: dir.appendingPathComponent("f.bin"))
        }
        return root
    }

    /// Recursively counts files and directories in a snapshot tree.
    private func count(_ node: FileNode) -> (files: Int, directories: Int) {
        var files = 0
        var directories = 0
        for child in node.children {
            if child.isDirectory {
                directories += 1
                let sub = count(child)
                files += sub.files
                directories += sub.directories
            } else {
                files += 1
            }
        }
        return (files, directories)
    }

    @Test func streamsSnapshotsAndProgressBeforeFinishing() async throws {
        let root = try makeChainFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        var sawSnapshotBeforeFinish = false
        var sawProgress = false
        var finishedTree: FileNode?

        let scanner = DiskScanner()
        for await event in scanner.scan(url: root, interval: 0.005) {
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
        let counts = finishedTree.map(count)
        #expect(counts?.files == chainDepth)
        #expect(counts?.directories == chainDepth)
        #expect(finishedTree?.allocatedSize == Int64(chainDepth * 4_096))
    }
}
