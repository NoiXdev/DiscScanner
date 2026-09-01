import Foundation

/// Mutable tree node used internally by the scanner. All mutation happens
/// under ScanState's lock; UI only ever sees immutable FileNode snapshots.
final class MutableNode {
    let name: String
    let path: String
    let isDirectory: Bool
    var allocatedSize: Int64 = 0
    var logicalSize: Int64 = 0
    var modificationDate: Date?
    var ownerID: Int32?
    var isAccessDenied = false
    var children: [MutableNode] = []
    weak var parent: MutableNode?

    init(name: String, path: String, isDirectory: Bool, parent: MutableNode?) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.parent = parent
    }

    /// Converts the subtree into an immutable snapshot. `maxDepth` limits how
    /// many child levels are copied (nil = unlimited): live UI snapshots use a
    /// depth cap so huge trees do not stall workers or the main thread; the
    /// final snapshot is always taken without a cap.
    func snapshot(maxDepth: Int? = nil) -> FileNode {
        let snapshotChildren: [FileNode]
        if let maxDepth, maxDepth <= 0 {
            snapshotChildren = []
        } else {
            let childDepth = maxDepth.map { $0 - 1 }
            snapshotChildren = children
                .map { $0.snapshot(maxDepth: childDepth) }
                .sorted { $0.allocatedSize > $1.allocatedSize }
        }
        return FileNode(
            name: name,
            path: path,
            isDirectory: isDirectory,
            allocatedSize: allocatedSize,
            logicalSize: logicalSize,
            modificationDate: modificationDate,
            ownerID: ownerID,
            isAccessDenied: isAccessDenied,
            children: snapshotChildren
        )
    }
}
