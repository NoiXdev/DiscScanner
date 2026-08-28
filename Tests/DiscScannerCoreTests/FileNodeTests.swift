import Testing
@testable import DiscScannerCore

struct FileNodeTests {
    private func makeTree() -> MutableNode {
        let root = MutableNode(name: "root", path: "/root", isDirectory: true, parent: nil)
        let sub = MutableNode(name: "sub", path: "/root/sub", isDirectory: true, parent: root)
        let small = MutableNode(name: "small.bin", path: "/root/small.bin", isDirectory: false, parent: root)
        small.allocatedSize = 100
        let big = MutableNode(name: "big.bin", path: "/root/sub/big.bin", isDirectory: false, parent: sub)
        big.allocatedSize = 500
        sub.children = [big]
        sub.allocatedSize = 500
        root.children = [small, sub]
        root.allocatedSize = 600
        return root
    }

    @Test func snapshotSortsChildrenBySizeDescending() {
        let node = makeTree().snapshot()
        #expect(node.children.map(\.name) == ["sub", "small.bin"])
        #expect(node.allocatedSize == 600)
    }

    @Test func idIsPath() {
        let node = makeTree().snapshot()
        #expect(node.id == "/root")
        #expect(node.children[0].id == "/root/sub")
    }

    @Test func findLocatesNestedNodes() {
        let node = makeTree().snapshot()
        #expect(node.find(path: "/root/sub/big.bin")?.allocatedSize == 500)
        #expect(node.find(path: "/root") != nil)
        #expect(node.find(path: "/root/nope") == nil)
        #expect(node.find(path: "/rootx") == nil)
    }

    @Test func outlineChildrenIsNilForFilesAndEmptyDirs() {
        let node = makeTree().snapshot()
        #expect(node.outlineChildren != nil)
        #expect(node.find(path: "/root/small.bin")?.outlineChildren == nil)
        let emptyDir = MutableNode(name: "e", path: "/e", isDirectory: true, parent: nil).snapshot()
        #expect(emptyDir.outlineChildren == nil)
    }
}
