import Foundation
import Testing
@testable import DiscScannerCore

private let mb: Int64 = 1024 * 1024

private func file(_ name: String, _ megabytes: Int64, in parent: String) -> FileNode {
    FileNode(
        name: name,
        path: "\(parent)/\(name)",
        isDirectory: false,
        allocatedSize: megabytes * mb,
        logicalSize: megabytes * mb / 2
    )
}

private func folder(_ name: String, _ path: String, _ children: [FileNode]) -> FileNode {
    FileNode(
        name: name,
        path: path,
        isDirectory: true,
        allocatedSize: children.reduce(0) { $0 + $1.allocatedSize },
        logicalSize: children.reduce(0) { $0 + $1.logicalSize },
        children: children
    )
}

private let before = folder("root", "/root", [
    folder("Users", "/root/Users", [
        file("photo.jpg", 100, in: "/root/Users"),
        file("old.zip", 50, in: "/root/Users"),
    ]),
    folder("System", "/root/System", [file("kernel", 10, in: "/root/System")]),
])

private let after = folder("root", "/root", [
    folder("Users", "/root/Users", [
        file("photo.jpg", 140, in: "/root/Users"),
        file("new.mov", 200, in: "/root/Users"),
    ]),
    folder("System", "/root/System", [file("kernel", 10, in: "/root/System")]),
])

@Test func comparisonReportsAddedRemovedAndChanged() {
    let result = SnapshotComparison.compare(baseline: before, current: after)
    let byPath = Dictionary(uniqueKeysWithValues: result.entries.map { ($0.path, $0) })

    #expect(byPath["/root/Users/new.mov"]?.kind == .added)
    #expect(byPath["/root/Users/old.zip"]?.kind == .removed)
    #expect(byPath["/root/Users/photo.jpg"]?.kind == .grown)
    #expect(byPath["/root/Users/photo.jpg"]?.delta == 40 * mb)
    // Unchanged branches stay out of the report entirely.
    #expect(byPath["/root/System"] == nil)
    #expect(byPath["/root/System/kernel"] == nil)
}

@Test func totalsComeFromTheRoots() {
    let result = SnapshotComparison.compare(baseline: before, current: after)
    #expect(result.oldTotal == 160 * mb)
    #expect(result.newTotal == 350 * mb)
    #expect(result.delta == 190 * mb)
    #expect(result.addedCount == 1)
    #expect(result.removedCount == 1)
    #expect(result.grownCount == 2)  // photo.jpg and the Users folder
    #expect(result.shrunkCount == 0)
}

@Test func entriesAreSortedByImpactNotBySign() {
    let result = SnapshotComparison.compare(baseline: before, current: after)
    let deltas = result.entries.map { abs($0.delta) }
    #expect(deltas == deltas.sorted(by: >))
    #expect(result.entries.first?.path == "/root/Users/new.mov")
}

@Test func theRootItselfIsNeverAnEntry() {
    let result = SnapshotComparison.compare(baseline: before, current: after)
    #expect(!result.entries.contains { $0.path == "/root" })
}

@Test func smallChangesAreFilteredOut() {
    let quiet = folder("root", "/root", [
        folder("Users", "/root/Users", [file("photo.jpg", 100, in: "/root/Users")]),
    ])
    let noisier = folder("root", "/root", [
        folder("Users", "/root/Users", [
            file("photo.jpg", 100, in: "/root/Users"),
            FileNode(name: "tiny.log", path: "/root/Users/tiny.log",
                     isDirectory: false, allocatedSize: 4096, logicalSize: 4096),
        ]),
    ])
    let noisy = SnapshotComparison.compare(
        baseline: quiet, current: noisier,
        options: ComparisonOptions(minimumDelta: 0)
    )
    #expect(noisy.entries.count == 2)  // the file and its folder

    let filtered = SnapshotComparison.compare(baseline: quiet, current: noisier)
    #expect(filtered.entries.isEmpty)
}

@Test func depthLimitCollapsesDeepChanges() {
    let deepBefore = folder("root", "/root", [
        folder("a", "/root/a", [folder("b", "/root/a/b", [file("c.bin", 10, in: "/root/a/b")])]),
    ])
    let deepAfter = folder("root", "/root", [
        folder("a", "/root/a", [folder("b", "/root/a/b", [file("c.bin", 90, in: "/root/a/b")])]),
    ])
    let shallow = SnapshotComparison.compare(
        baseline: deepBefore, current: deepAfter,
        options: ComparisonOptions(maximumDepth: 1)
    )
    #expect(shallow.entries.map(\.path) == ["/root/a"])

    let deep = SnapshotComparison.compare(
        baseline: deepBefore, current: deepAfter,
        options: ComparisonOptions(maximumDepth: nil)
    )
    #expect(deep.entries.map(\.path) == ["/root/a", "/root/a/b", "/root/a/b/c.bin"])
}

@Test func removedSubtreesAreOneEntry() {
    let withFolder = folder("root", "/root", [
        folder("Cache", "/root/Cache", [
            file("one.bin", 30, in: "/root/Cache"),
            file("two.bin", 30, in: "/root/Cache"),
        ]),
    ])
    let withoutFolder = folder("root", "/root", [])
    let result = SnapshotComparison.compare(baseline: withFolder, current: withoutFolder)
    #expect(result.entries.map(\.path) == ["/root/Cache"])
    #expect(result.entries.first?.kind == .removed)
    #expect(result.entries.first?.oldSize == 60 * mb)
}

@Test func logicalModeComparesLogicalSizes() {
    let result = SnapshotComparison.compare(
        baseline: before, current: after,
        options: ComparisonOptions(sizeMode: .logical)
    )
    #expect(result.oldTotal == 80 * mb)
    #expect(result.newTotal == 175 * mb)
}

@Test func truncationIsReported() {
    let many = (1...20).map { file("f\($0).bin", Int64($0), in: "/root") }
    let result = SnapshotComparison.compare(
        baseline: folder("root", "/root", []),
        current: folder("root", "/root", many),
        options: ComparisonOptions(limit: 5)
    )
    #expect(result.entries.count == 5)
    #expect(result.isTruncated)
    #expect(result.addedCount == 20)  // counted before the cut
}
