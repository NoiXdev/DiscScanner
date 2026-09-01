import Foundation

public struct FileNode: Identifiable, Sendable, Equatable {
    public let name: String
    public let path: String
    public let isDirectory: Bool
    /// Bytes the item occupies on disk, children included for directories.
    public let allocatedSize: Int64
    /// Byte length of the content. Smaller than `allocatedSize` for sparse or
    /// compressed files, larger for many tiny files sharing a block.
    public let logicalSize: Int64
    public let modificationDate: Date?
    /// Numeric owner (uid). Names are resolved on demand: a volume scan holds
    /// millions of nodes and a uid costs four bytes where a name costs more.
    public let ownerID: Int32?
    public let isAccessDenied: Bool
    public let children: [FileNode]

    public var id: String { path }

    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        allocatedSize: Int64,
        logicalSize: Int64 = 0,
        modificationDate: Date? = nil,
        ownerID: Int32? = nil,
        isAccessDenied: Bool = false,
        children: [FileNode] = []
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.allocatedSize = allocatedSize
        self.logicalSize = logicalSize
        self.modificationDate = modificationDate
        self.ownerID = ownerID
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

    /// Lowercased file extension without the dot; empty for directories and
    /// for names that carry none (a leading dot is a hidden file, not an
    /// extension).
    var fileExtension: String {
        guard !isDirectory else { return "" }
        guard
            let dot = name.lastIndex(of: "."),
            dot != name.startIndex,
            dot != name.index(before: name.endIndex)
        else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }

    func size(_ mode: SizeMode) -> Int64 {
        mode == .allocated ? allocatedSize : logicalSize
    }
}

/// Which of the two sizes a view or statistic reports.
public enum SizeMode: String, CaseIterable, Sendable, Codable, Identifiable {
    case allocated
    case logical

    public var id: String { rawValue }
}

// A scan is written to disk as JSON (see ScanStore), so the keys are kept to
// one character each: a volume scan serialises millions of nodes and the key
// names would otherwise dominate the file. Every field except the name is
// optional on read, so a file written by an older or newer build still loads.
extension FileNode: Codable {
    private enum CodingKeys: String, CodingKey {
        case name = "n"
        case path = "p"
        case isDirectory = "d"
        case allocatedSize = "a"
        case logicalSize = "l"
        case modificationDate = "m"
        case ownerID = "o"
        case isAccessDenied = "x"
        case children = "c"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try container.decode(String.self, forKey: .name),
            path: try container.decodeIfPresent(String.self, forKey: .path) ?? "",
            isDirectory: try container.decodeIfPresent(Bool.self, forKey: .isDirectory) ?? false,
            allocatedSize: try container.decodeIfPresent(Int64.self, forKey: .allocatedSize) ?? 0,
            logicalSize: try container.decodeIfPresent(Int64.self, forKey: .logicalSize) ?? 0,
            modificationDate: try container.decodeIfPresent(Date.self, forKey: .modificationDate),
            ownerID: try container.decodeIfPresent(Int32.self, forKey: .ownerID),
            isAccessDenied: try container.decodeIfPresent(Bool.self, forKey: .isAccessDenied) ?? false,
            children: try container.decodeIfPresent([FileNode].self, forKey: .children) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        // Defaults are dropped rather than written: most nodes are readable
        // files with no children, and those keys make up the bulk of a scan.
        if isDirectory { try container.encode(true, forKey: .isDirectory) }
        if allocatedSize != 0 { try container.encode(allocatedSize, forKey: .allocatedSize) }
        if logicalSize != 0 { try container.encode(logicalSize, forKey: .logicalSize) }
        try container.encodeIfPresent(modificationDate, forKey: .modificationDate)
        try container.encodeIfPresent(ownerID, forKey: .ownerID)
        if isAccessDenied { try container.encode(true, forKey: .isAccessDenied) }
        if !children.isEmpty { try container.encode(children, forKey: .children) }
    }
}
