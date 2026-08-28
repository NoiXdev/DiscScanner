import Foundation

/// Mutable tree node used internally by the scanner. All mutation happens
/// under ScanState's lock; UI only ever sees immutable FileNode snapshots.
final class MutableNode {
    let name: String
    let path: String
    let isDirectory: Bool
    var allocatedSize: Int64 = 0
    var isAccessDenied = false
    var children: [MutableNode] = []
    weak var parent: MutableNode?

    init(name: String, path: String, isDirectory: Bool, parent: MutableNode?) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.parent = parent
    }

    func snapshot() -> FileNode {
        FileNode(
            name: name,
            path: path,
            isDirectory: isDirectory,
            allocatedSize: allocatedSize,
            isAccessDenied: isAccessDenied,
            children: children.map { $0.snapshot() }.sorted { $0.allocatedSize > $1.allocatedSize }
        )
    }
}
