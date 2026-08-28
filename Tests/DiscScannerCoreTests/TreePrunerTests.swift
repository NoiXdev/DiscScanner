import Testing
@testable import DiscScannerCore

struct TreePrunerTests {
    /// root(350) { sub(250) { b.bin(200), c.bin(50) }, a.bin(100) }
    private func makeTree() -> FileNode {
        FileNode(
            name: "root", path: "/root", isDirectory: true, allocatedSize: 350,
            children: [
                FileNode(
                    name: "sub", path: "/root/sub", isDirectory: true, allocatedSize: 250,
                    children: [
                        FileNode(name: "b.bin", path: "/root/sub/b.bin", isDirectory: false, allocatedSize: 200),
                        FileNode(name: "c.bin", path: "/root/sub/c.bin", isDirectory: false, allocatedSize: 50),
                    ]
                ),
                FileNode(name: "a.bin", path: "/root/a.bin", isDirectory: false, allocatedSize: 100),
            ]
        )
    }

    @Test func removesFileAndReaggregatesAncestorSizes() {
        let pruned = TreePruner.removing(paths: ["/root/sub/b.bin"], from: makeTree())
        #expect(pruned?.allocatedSize == 150)
        #expect(pruned?.find(path: "/root/sub")?.allocatedSize == 50)
        #expect(pruned?.find(path: "/root/sub/b.bin") == nil)
        #expect(pruned?.find(path: "/root/sub/c.bin") != nil)
    }

    @Test func removesDirectorySubtree() {
        let pruned = TreePruner.removing(paths: ["/root/sub"], from: makeTree())
        #expect(pruned?.allocatedSize == 100)
        #expect(pruned?.find(path: "/root/sub") == nil)
        #expect(pruned?.children.count == 1)
    }

    @Test func removingRootReturnsNil() {
        #expect(TreePruner.removing(paths: ["/root"], from: makeTree()) == nil)
    }

    @Test func resortsChildrenAfterRemoval() {
        // removing b.bin makes sub (50) smaller than a.bin (100)
        let pruned = TreePruner.removing(paths: ["/root/sub/b.bin"], from: makeTree())
        #expect(pruned?.children.map(\.name) == ["a.bin", "sub"])
    }
}
