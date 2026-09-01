import Foundation
import Testing
@testable import DiscScannerCore

private func node(_ name: String, _ size: Int64, isDirectory: Bool = false) -> FileNode {
    FileNode(
        name: name,
        path: "/root/\(name)",
        isDirectory: isDirectory,
        allocatedSize: size,
        logicalSize: size / 2
    )
}

private func root(_ children: [FileNode]) -> FileNode {
    FileNode(
        name: "root",
        path: "/root",
        isDirectory: true,
        allocatedSize: children.reduce(0) { $0 + $1.allocatedSize },
        logicalSize: children.reduce(0) { $0 + $1.logicalSize },
        children: children
    )
}

@Test func slicesAreSortedAndFractionsSumToOne() {
    let slices = ChartSlices.make(for: root([
        node("Users", 300, isDirectory: true),
        node("Windows", 500, isDirectory: true),
        node("Data", 200, isDirectory: true),
    ]))
    #expect(slices.map(\.name) == ["Windows", "Users", "Data"])
    #expect(abs(slices.reduce(0) { $0 + $1.fraction } - 1) < 0.0001)
    #expect(slices.first?.path == "/root/Windows")
}

@Test func looseFilesCollapseIntoOneSlice() throws {
    let slices = ChartSlices.make(for: root([
        node("Users", 100, isDirectory: true),
        node("a.bin", 30),
        node("b.bin", 20),
        node("c.bin", 10),
    ]))
    #expect(slices.count == 2)
    let loose = try #require(slices.first { $0.kind == .looseFiles })
    #expect(loose.size == 60)
    #expect(loose.itemCount == 3)
    #expect(loose.path == nil)
}

@Test func aSingleLooseFileKeepsItsName() {
    let slices = ChartSlices.make(for: root([
        node("Users", 100, isDirectory: true),
        node("a.bin", 30),
    ]))
    #expect(slices.map(\.kind) == [.directory, .file])
    #expect(slices.last?.name == "a.bin")
    #expect(slices.last?.path == "/root/a.bin")
}

@Test func groupingCanBeTurnedOff() {
    let slices = ChartSlices.make(
        for: root([node("Users", 100, isDirectory: true), node("a.bin", 30), node("b.bin", 20)]),
        options: ChartSliceOptions(groupLooseFiles: false)
    )
    #expect(slices.count == 3)
    #expect(slices.allSatisfy { $0.kind != .looseFiles })
}

@Test func theTailBecomesOthers() throws {
    let children = (1...10).map { node("d\($0)", Int64($0) * 100, isDirectory: true) }
    let slices = ChartSlices.make(
        for: root(children),
        options: ChartSliceOptions(maximumSlices: 3)
    )
    #expect(slices.count == 4)
    #expect(Array(slices.map(\.size).prefix(3)) == [1000, 900, 800])
    let others = try #require(slices.last)
    #expect(others.kind == .others)
    // 700 + 600 + 500 + 400 + 300 + 200 + 100, written out: inside the
    // #expect expansion a bare literal sum is type-checked on its own and
    // settles on Int, which then never equals the Int64 it is compared to.
    #expect(others.size == 2800)
    #expect(others.itemCount == 7)
}

@Test func freeSpaceIsItsOwnSliceAndCountsTowardTheTotal() {
    let slices = ChartSlices.make(
        for: root([node("Users", 250, isDirectory: true)]),
        options: ChartSliceOptions(freeSpace: 750)
    )
    #expect(slices.count == 2)
    #expect(slices.last?.kind == .freeSpace)
    #expect(abs((slices.first?.fraction ?? 0) - 0.25) < 0.0001)
    #expect(abs((slices.last?.fraction ?? 0) - 0.75) < 0.0001)
}

@Test func logicalModeUsesTheOtherSize() {
    let slices = ChartSlices.make(
        for: root([node("Users", 400, isDirectory: true)]),
        options: ChartSliceOptions(sizeMode: .logical)
    )
    #expect(slices.first?.size == 200)
}

@Test func anEmptyFolderYieldsNoSlices() {
    #expect(ChartSlices.make(for: root([])).isEmpty)
}
