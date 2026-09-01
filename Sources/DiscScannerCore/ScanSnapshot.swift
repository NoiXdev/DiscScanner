import Foundation

/// The part of a saved scan the History tab lists: small enough to read
/// without touching the tree, which for a volume scan is hundreds of MB.
public struct ScanSnapshotSummary: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let rootPath: String
    /// What to call the scan in a list — the volume name, or the folder.
    public var displayName: String
    public var note: String
    public let fileCount: Int
    public let directoryCount: Int
    public let accessDeniedCount: Int
    public let totalAllocatedSize: Int64
    public let totalLogicalSize: Int64
    public let volumeFreeSpace: Int64?
    public let volumeTotalCapacity: Int64?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        rootPath: String,
        displayName: String,
        note: String = "",
        fileCount: Int,
        directoryCount: Int,
        accessDeniedCount: Int = 0,
        totalAllocatedSize: Int64,
        totalLogicalSize: Int64 = 0,
        volumeFreeSpace: Int64? = nil,
        volumeTotalCapacity: Int64? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rootPath = rootPath
        self.displayName = displayName
        self.note = note
        self.fileCount = fileCount
        self.directoryCount = directoryCount
        self.accessDeniedCount = accessDeniedCount
        self.totalAllocatedSize = totalAllocatedSize
        self.totalLogicalSize = totalLogicalSize
        self.volumeFreeSpace = volumeFreeSpace
        self.volumeTotalCapacity = volumeTotalCapacity
    }

    public func size(_ mode: SizeMode) -> Int64 {
        mode == .allocated ? totalAllocatedSize : totalLogicalSize
    }
}

/// A finished scan, ready to be written to disk or compared against another.
public struct ScanSnapshot: Identifiable, Sendable, Equatable {
    public var summary: ScanSnapshotSummary
    public var root: FileNode

    public var id: UUID { summary.id }

    public init(summary: ScanSnapshotSummary, root: FileNode) {
        self.summary = summary
        self.root = root
    }

    /// Derives the summary from the tree, so the two can never disagree.
    public init(
        root: FileNode,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        displayName: String? = nil,
        note: String = "",
        accessDeniedCount: Int = 0,
        volumeFreeSpace: Int64? = nil,
        volumeTotalCapacity: Int64? = nil,
        statistics: FileStatistics? = nil
    ) {
        let stats = statistics ?? FileStatistics.compute(root: root, topFileLimit: 1)
        self.root = root
        self.summary = ScanSnapshotSummary(
            id: id,
            createdAt: createdAt,
            rootPath: root.path,
            displayName: displayName ?? (root.name.isEmpty ? root.path : root.name),
            note: note,
            fileCount: stats.fileCount,
            directoryCount: stats.directoryCount,
            accessDeniedCount: accessDeniedCount,
            totalAllocatedSize: root.allocatedSize,
            totalLogicalSize: root.logicalSize,
            volumeFreeSpace: volumeFreeSpace,
            volumeTotalCapacity: volumeTotalCapacity
        )
    }
}
