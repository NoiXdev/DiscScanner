import Foundation
import Testing
@testable import DiscScannerCore

private func makeTree(extraFile: Bool = false) -> FileNode {
    var children: [FileNode] = [
        FileNode(
            name: "movie.mov",
            path: "/root/movie.mov",
            isDirectory: false,
            allocatedSize: 1000,
            logicalSize: 900,
            modificationDate: Date(timeIntervalSince1970: 1_700_000_000),
            ownerID: 501
        ),
        FileNode(
            name: "sub",
            path: "/root/sub",
            isDirectory: true,
            allocatedSize: 20,
            logicalSize: 20,
            isAccessDenied: true,
            children: [
                FileNode(name: "x.txt", path: "/root/sub/x.txt", isDirectory: false,
                         allocatedSize: 20, logicalSize: 20),
            ]
        ),
    ]
    if extraFile {
        children.append(FileNode(name: "new.bin", path: "/root/new.bin",
                                 isDirectory: false, allocatedSize: 500, logicalSize: 500))
    }
    return FileNode(
        name: "root",
        path: "/root",
        isDirectory: true,
        allocatedSize: children.reduce(0) { $0 + $1.allocatedSize },
        logicalSize: children.reduce(0) { $0 + $1.logicalSize },
        children: children
    )
}

private func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("DiscScannerTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url) }
    return try body(url)
}

@Test func snapshotSurvivesARoundTrip() throws {
    try withTemporaryDirectory { directory in
        let snapshot = ScanSnapshot(
            root: makeTree(),
            // A whole-second date: the round trip goes through JSON, and the
            // test is about the payload, not about float formatting.
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            displayName: "Macintosh HD",
            accessDeniedCount: 1,
            volumeFreeSpace: 5_000,
            volumeTotalCapacity: 10_000
        )
        let entry = try ScanStore.save(snapshot, in: directory)
        let loaded = try ScanStore.read(at: entry.url)

        #expect(loaded.root == snapshot.root)
        #expect(loaded.summary == snapshot.summary)
        #expect(loaded.summary.displayName == "Macintosh HD")
        #expect(loaded.summary.fileCount == 2)
        #expect(loaded.summary.totalAllocatedSize == 1020)
        #expect(loaded.summary.volumeFreeSpace == 5_000)
        // The metadata a file keeps is the point of saving it at all.
        #expect(loaded.root.children.first?.modificationDate
            == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(loaded.root.children.first?.ownerID == 501)
        #expect(loaded.root.children.last?.isAccessDenied == true)
    }
}

@Test func summaryIsReadableWithoutTheTree() throws {
    try withTemporaryDirectory { directory in
        let snapshot = ScanSnapshot(
            root: makeTree(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            displayName: "Volume"
        )
        let entry = try ScanStore.save(snapshot, in: directory)
        #expect(try ScanStore.readSummary(at: entry.url) == snapshot.summary)
    }
}

@Test func listingIsNewestFirstAndSkipsForeignFiles() throws {
    try withTemporaryDirectory { directory in
        let older = ScanSnapshot(
            root: makeTree(),
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            displayName: "older"
        )
        let newer = ScanSnapshot(
            root: makeTree(extraFile: true),
            createdAt: Date(timeIntervalSince1970: 2_000_000),
            displayName: "newer"
        )
        try ScanStore.save(older, in: directory)
        try ScanStore.save(newer, in: directory)
        try Data("not a scan".utf8)
            .write(to: directory.appendingPathComponent("junk.dscan"))
        try Data("{}".utf8)
            .write(to: directory.appendingPathComponent("notes.txt"))

        let entries = try ScanStore.list(in: directory)
        #expect(entries.map(\.summary.displayName) == ["newer", "older"])
    }
}

@Test func savingTwiceInTheSameSecondKeepsBothFiles() throws {
    try withTemporaryDirectory { directory in
        let date = Date(timeIntervalSince1970: 1_500_000)
        let first = ScanSnapshot(root: makeTree(), createdAt: date, displayName: "same")
        let second = ScanSnapshot(root: makeTree(), createdAt: date, displayName: "same")
        let a = try ScanStore.save(first, in: directory)
        let b = try ScanStore.save(second, in: directory)
        #expect(a.url != b.url)
        #expect(try ScanStore.list(in: directory).count == 2)
    }
}

@Test func deletingRemovesTheFile() throws {
    try withTemporaryDirectory { directory in
        let entry = try ScanStore.save(ScanSnapshot(root: makeTree()), in: directory)
        try ScanStore.delete(at: entry.url)
        #expect(try ScanStore.list(in: directory).isEmpty)
    }
}

@Test func readingSomethingElseFails() throws {
    try withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("broken.dscan")
        try Data("no newline, no scan".utf8).write(to: url)
        #expect(throws: ScanStore.StoreError.malformedFile(url.path)) {
            try ScanStore.read(at: url)
        }
    }
}

@Test func summaryIsDerivedFromTheTree() {
    let snapshot = ScanSnapshot(root: makeTree(extraFile: true))
    #expect(snapshot.summary.fileCount == 3)
    #expect(snapshot.summary.directoryCount == 1)
    #expect(snapshot.summary.totalAllocatedSize == 1520)
    #expect(snapshot.summary.rootPath == "/root")
    #expect(snapshot.summary.displayName == "root")
}
