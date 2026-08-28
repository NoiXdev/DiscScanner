import Foundation

public struct FileNode: Identifiable, Sendable, Equatable {
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let allocatedSize: Int64
    public let isAccessDenied: Bool
    public let children: [FileNode]

    public var id: String { path }

    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        allocatedSize: Int64,
        isAccessDenied: Bool = false,
        children: [FileNode] = []
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.allocatedSize = allocatedSize
        self.isAccessDenied = isAccessDenied
        self.children = children
    }
}

public extension FileNode {
    /// Children for outline/disclosure UIs: nil for files and empty directories.
    var outlineChildren: [FileNode]? {
        isDirectory && !children.isEmpty ? children : nil
    }

    /// Depth-first lookup by absolute path. Prunes branches that are not path prefixes.
    func find(path: String) -> FileNode? {
        if self.path == path { return self }
        let prefix = self.path.hasSuffix("/") ? self.path : self.path + "/"
        guard path.hasPrefix(prefix) else { return nil }
        for child in children {
            if let found = child.find(path: path) { return found }
        }
        return nil
    }
}
