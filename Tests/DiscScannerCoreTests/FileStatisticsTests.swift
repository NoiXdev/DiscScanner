import Foundation
import Testing
@testable import DiscScannerCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func file(
    _ name: String,
    _ allocated: Int64,
    logical: Int64? = nil,
    ageInDays: Double? = 0,
    owner: Int32? = 501,
    in parent: String = "/root"
) -> FileNode {
    FileNode(
        name: name,
        path: "\(parent)/\(name)",
        isDirectory: false,
        allocatedSize: allocated,
        logicalSize: logical ?? allocated,
        modificationDate: ageInDays.map { now.addingTimeInterval(-$0 * 86_400) },
        ownerID: owner
    )
}

private func directory(_ name: String, _ children: [FileNode], path: String? = nil) -> FileNode {
    FileNode(
        name: name,
        path: path ?? "/\(name)",
        isDirectory: true,
        allocatedSize: children.reduce(0) { $0 + $1.allocatedSize },
        logicalSize: children.reduce(0) { $0 + $1.logicalSize },
        children: children
    )
}

private let sampleTree = directory("root", [
    file("a.jpg", 300),
    file("b.jpg", 200),
    file("notes.txt", 50, ageInDays: 400),
    file("README", 10, ageInDays: nil),
    directory("sub", [
        file("c.JPG", 100, in: "/root/sub"),
        file("d.mov", 1000, logical: 900, ageInDays: 10, owner: 502, in: "/root/sub"),
    ], path: "/root/sub"),
], path: "/root")

@Test func statisticsCountFilesAndDirectories() {
    let stats = FileStatistics.compute(root: sampleTree, now: now)
    #expect(stats.fileCount == 6)
    #expect(stats.directoryCount == 1)
    #expect(stats.totalAllocatedSize == 1660)
    #expect(stats.totalLogicalSize == 1560)
}

@Test func extensionsAreCaseInsensitiveAndSortedBySize() {
    let stats = FileStatistics.compute(root: sampleTree, now: now)
    let byExtension = Dictionary(uniqueKeysWithValues: stats.extensions.map { ($0.fileExtension, $0) })
    #expect(byExtension["jpg"]?.fileCount == 3)
    #expect(byExtension["jpg"]?.allocatedSize == 600)
    #expect(byExtension["mov"]?.logicalSize == 900)
    // "README" has no extension; a leading dot would not make one either.
    #expect(byExtension[""]?.fileCount == 1)
    #expect(stats.extensions.first?.fileExtension == "mov")
}

@Test func hiddenFilesHaveNoExtension() {
    #expect(file(".zshrc", 1).fileExtension == "")
    #expect(file("archive.tar.gz", 1).fileExtension == "gz")
    #expect(file("trailing.", 1).fileExtension == "")
    #expect(directory("dir.d", []).fileExtension == "")
}

@Test func ownersAreGroupedByUID() {
    let stats = FileStatistics.compute(root: sampleTree, now: now)
    #expect(stats.owners.count == 2)
    #expect(stats.owners.first?.ownerID == 502)
    #expect(stats.owners.first?.allocatedSize == 1000)
    #expect(stats.owners.last?.fileCount == 5)
}

@Test func agesFallIntoBuckets() {
    let stats = FileStatistics.compute(root: sampleTree, now: now)
    let byBucket = Dictionary(uniqueKeysWithValues: stats.ages.map { ($0.bucket, $0) })
    #expect(byBucket[.today]?.fileCount == 3)
    #expect(byBucket[.month]?.fileCount == 1)   // 10 days
    #expect(byBucket[.twoYears]?.fileCount == 1) // 400 days
    #expect(byBucket[.unknown]?.fileCount == 1)
    #expect(byBucket[.week] == nil)              // empty buckets are dropped
    // Canonical order, not size order.
    #expect(stats.ages.map(\.bucket) == [.today, .month, .twoYears, .unknown])
}

@Test func ageBucketBoundariesAreExclusiveUpperBounds() {
    #expect(FileAgeBucket.bucket(forAgeInDays: 0) == .today)
    #expect(FileAgeBucket.bucket(forAgeInDays: 1) == .week)
    #expect(FileAgeBucket.bucket(forAgeInDays: 6.9) == .week)
    #expect(FileAgeBucket.bucket(forAgeInDays: 7) == .month)
    #expect(FileAgeBucket.bucket(forAgeInDays: 364) == .year)
    #expect(FileAgeBucket.bucket(forAgeInDays: 730) == .older)
    #expect(FileAgeBucket.bucket(forAgeInDays: 100_000) == .older)
}

@Test func topFilesAreTheLargestOnesInOrder() {
    let stats = FileStatistics.compute(root: sampleTree, now: now, topFileLimit: 3)
    #expect(stats.topFiles.map(\.name) == ["d.mov", "a.jpg", "b.jpg"])
    #expect(stats.topFiles.first?.path == "/root/sub/d.mov")
}

@Test func topFilesSurviveTheBoundedCollector() {
    // More files than twice the limit forces the collector to prune, which
    // is where an off-by-one would drop the actual largest file.
    let children = (1...50).map { file("f\($0).bin", Int64($0)) }
    let stats = FileStatistics.compute(root: directory("root", children), topFileLimit: 5)
    #expect(stats.topFiles.map(\.allocatedSize) == [50, 49, 48, 47, 46])
}

@Test func emptyTreeYieldsEmptyStatistics() {
    let stats = FileStatistics.compute(root: directory("root", []))
    #expect(stats.fileCount == 0)
    #expect(stats.directoryCount == 0)
    #expect(stats.extensions.isEmpty)
    #expect(stats.topFiles.isEmpty)
}
