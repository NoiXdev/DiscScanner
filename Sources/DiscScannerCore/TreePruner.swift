import Foundation

public enum TreePruner {
    /// Rebuilds the snapshot tree without the given paths. Directory sizes
    /// become the sum of their remaining children so ancestors shrink
    /// accordingly; no rescan needed.
    public static func removing(paths: Set<String>, from node: FileNode) -> FileNode? {
        guard !paths.contains(node.path) else { return nil }
        guard node.isDirectory else { return node }

        let newChildren = node.children
            .compactMap { removing(paths: paths, from: $0) }
            .sorted { $0.allocatedSize > $1.allocatedSize }
        let newSize = newChildren.reduce(Int64(0)) { $0 + $1.allocatedSize }

        return FileNode(
            name: node.name,
            path: node.path,
            isDirectory: true,
            allocatedSize: newSize,
            isAccessDenied: node.isAccessDenied,
            children: newChildren
        )
    }
}
