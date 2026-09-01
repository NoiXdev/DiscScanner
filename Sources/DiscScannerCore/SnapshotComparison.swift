import Foundation

/// One line of a comparison: what a path weighed before, what it weighs now.
public struct ChangeEntry: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case added
        case removed
        case grown
        case shrunk
    }

    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let depth: Int
    public let oldSize: Int64
    public let newSize: Int64

    public var id: String { path }
    public var delta: Int64 { newSize - oldSize }

    public var kind: Kind {
        if oldSize == 0, newSize > 0 { return .added }
        if newSize == 0, oldSize > 0 { return .removed }
        return delta >= 0 ? .grown : .shrunk
    }

    public init(
        path: String,
        name: String,
        isDirectory: Bool,
        depth: Int,
        oldSize: Int64,
        newSize: Int64
    ) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.depth = depth
        self.oldSize = oldSize
        self.newSize = newSize
    }
}

public struct ComparisonOptions: Sendable, Equatable {
    public var sizeMode: SizeMode
    /// How deep to walk before a subtree is reported as a single line. nil
    /// walks the whole tree; the default keeps a volume comparison readable.
    public var maximumDepth: Int?
    /// Changes below this many bytes are noise, not news.
    public var minimumDelta: Int64
    /// Cap on the returned list, applied after sorting by impact.
    public var limit: Int

    public init(
        sizeMode: SizeMode = .allocated,
        maximumDepth: Int? = 6,
        minimumDelta: Int64 = 1024 * 1024,
        limit: Int = 500
    ) {
        self.sizeMode = sizeMode
        self.maximumDepth = maximumDepth
        self.minimumDelta = minimumDelta
        self.limit = limit
    }
}

public struct ComparisonResult: Sendable, Equatable {
    public var entries: [ChangeEntry] = []
    public var oldTotal: Int64 = 0
    public var newTotal: Int64 = 0
    public var addedCount = 0
    public var removedCount = 0
    public var grownCount = 0
    public var shrunkCount = 0
    /// True when the walk stopped early and the list is a prefix.
    public var isTruncated = false

    public var delta: Int64 { newTotal - oldTotal }

    public init() {}
}

public enum SnapshotComparison {
    /// Pairs two trees by path and reports what changed, biggest impact
    /// first. An added or removed directory is one line — its whole subtree
    /// changed with it, and listing every file inside says nothing more.
    public static func compare(
        baseline: FileNode,
        current: FileNode,
        options: ComparisonOptions = ComparisonOptions()
    ) -> ComparisonResult {
        var result = ComparisonResult()
        result.oldTotal = baseline.size(options.sizeMode)
        result.newTotal = current.size(options.sizeMode)

        var entries: [ChangeEntry] = []
        walk(baseline: baseline, current: current, depth: 0, options: options, into: &entries)

        // Biggest impact first; the path breaks ties so the same two trees
        // always compare to the same list.
        entries.sort {
            let left = abs($0.delta)
            let right = abs($1.delta)
            return left == right ? $0.path < $1.path : left > right
        }
        for entry in entries {
            switch entry.kind {
            case .added: result.addedCount += 1
            case .removed: result.removedCount += 1
            case .grown: result.grownCount += 1
            case .shrunk: result.shrunkCount += 1
            }
        }
        result.isTruncated = entries.count > options.limit
        result.entries = Array(entries.prefix(options.limit))
        return result
    }

    private static func walk(
        baseline: FileNode?,
        current: FileNode?,
        depth: Int,
        options: ComparisonOptions,
        into entries: inout [ChangeEntry]
    ) {
        let node = current ?? baseline
        guard let node else { return }
        let oldSize = baseline?.size(options.sizeMode) ?? 0
        let newSize = current?.size(options.sizeMode) ?? 0

        // A node that did not change is not news, whatever the threshold is.
        let delta = newSize - oldSize
        if depth > 0, delta != 0, abs(delta) >= options.minimumDelta {
            entries.append(ChangeEntry(
                path: node.path,
                name: node.name,
                isDirectory: node.isDirectory,
                depth: depth,
                oldSize: oldSize,
                newSize: newSize
            ))
        }

        // One side is gone: the subtree changed as a whole, stop here.
        guard let baseline, let current else { return }
        if let maximumDepth = options.maximumDepth, depth >= maximumDepth { return }

        var oldChildren: [String: FileNode] = [:]
        oldChildren.reserveCapacity(baseline.children.count)
        for child in baseline.children { oldChildren[child.name] = child }

        for child in current.children {
            let match = oldChildren.removeValue(forKey: child.name)
            walk(baseline: match, current: child, depth: depth + 1, options: options, into: &entries)
        }
        for removed in oldChildren.values {
            walk(baseline: removed, current: nil, depth: depth + 1, options: options, into: &entries)
        }
    }
}
