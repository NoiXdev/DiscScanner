import Foundation

public struct ExtensionStat: Identifiable, Sendable, Equatable {
    /// Lowercased, without the dot. Empty means "no extension".
    public let fileExtension: String
    public var fileCount: Int
    public var allocatedSize: Int64
    public var logicalSize: Int64

    public var id: String { fileExtension }

    public init(
        fileExtension: String,
        fileCount: Int = 0,
        allocatedSize: Int64 = 0,
        logicalSize: Int64 = 0
    ) {
        self.fileExtension = fileExtension
        self.fileCount = fileCount
        self.allocatedSize = allocatedSize
        self.logicalSize = logicalSize
    }
}

public struct OwnerStat: Identifiable, Sendable, Equatable {
    public let ownerID: Int32?
    /// Account name where the uid resolves, the bare uid otherwise.
    public let name: String
    public var fileCount: Int
    public var allocatedSize: Int64
    public var logicalSize: Int64

    public var id: String { ownerID.map(String.init) ?? "?" }

    public init(
        ownerID: Int32?,
        name: String,
        fileCount: Int = 0,
        allocatedSize: Int64 = 0,
        logicalSize: Int64 = 0
    ) {
        self.ownerID = ownerID
        self.name = name
        self.fileCount = fileCount
        self.allocatedSize = allocatedSize
        self.logicalSize = logicalSize
    }
}

/// How long ago a file was last modified. Buckets, not exact ages: the point
/// is "what can I archive", and that question is answered in orders of
/// magnitude.
public enum FileAgeBucket: String, CaseIterable, Sendable, Identifiable {
    case today
    case week
    case month
    case quarter
    case year
    case twoYears
    case older
    case unknown

    public var id: String { rawValue }

    /// Upper bound in days, nil for the open-ended buckets.
    public var maximumAgeInDays: Double? {
        switch self {
        case .today: return 1
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        case .twoYears: return 730
        case .older, .unknown: return nil
        }
    }

    public static func bucket(forAgeInDays days: Double) -> FileAgeBucket {
        for bucket in FileAgeBucket.allCases {
            if let limit = bucket.maximumAgeInDays, days < limit { return bucket }
        }
        return .older
    }
}

public struct AgeStat: Identifiable, Sendable, Equatable {
    public let bucket: FileAgeBucket
    public var fileCount: Int
    public var allocatedSize: Int64
    public var logicalSize: Int64

    public var id: String { bucket.rawValue }

    public init(
        bucket: FileAgeBucket,
        fileCount: Int = 0,
        allocatedSize: Int64 = 0,
        logicalSize: Int64 = 0
    ) {
        self.bucket = bucket
        self.fileCount = fileCount
        self.allocatedSize = allocatedSize
        self.logicalSize = logicalSize
    }
}

public struct TopFile: Identifiable, Sendable, Equatable {
    public let name: String
    public let path: String
    public let allocatedSize: Int64
    public let logicalSize: Int64
    public let modificationDate: Date?

    public var id: String { path }

    public init(node: FileNode) {
        self.name = node.name
        self.path = node.path
        self.allocatedSize = node.allocatedSize
        self.logicalSize = node.logicalSize
        self.modificationDate = node.modificationDate
    }
}

/// Everything the Extensions / Users / Age-of-files / Top-files tabs show,
/// gathered in a single pass over the tree — a volume scan has millions of
/// nodes and walking it once per tab would be felt.
public struct FileStatistics: Sendable, Equatable {
    public var extensions: [ExtensionStat] = []
    public var owners: [OwnerStat] = []
    public var ages: [AgeStat] = []
    public var topFiles: [TopFile] = []
    public var fileCount = 0
    public var directoryCount = 0
    public var totalAllocatedSize: Int64 = 0
    public var totalLogicalSize: Int64 = 0

    public init() {}

    /// Lists are sorted by allocated size, largest first. `topFileLimit`
    /// caps the Top-files list; the walk keeps only that many candidates
    /// rather than sorting every file on the volume.
    public static func compute(
        root: FileNode,
        now: Date = Date(),
        topFileLimit: Int = 200
    ) -> FileStatistics {
        var extensions: [String: ExtensionStat] = [:]
        var owners: [Int32?: OwnerStat] = [:]
        var ages: [FileAgeBucket: AgeStat] = [:]
        var result = FileStatistics()

        // Bounded top-N: collect up to twice the limit, then sort and cut.
        // Amortised O(n), and never holds the whole file list in memory.
        var candidates: [FileNode] = []
        var threshold: Int64 = 0
        func offer(_ node: FileNode) {
            guard node.allocatedSize >= threshold else { return }
            candidates.append(node)
            if candidates.count >= topFileLimit * 2 {
                candidates.sort { $0.allocatedSize > $1.allocatedSize }
                candidates.removeLast(candidates.count - topFileLimit)
                threshold = candidates.last?.allocatedSize ?? 0
            }
        }

        var stack: [FileNode] = [root]
        while let node = stack.popLast() {
            if node.isDirectory {
                result.directoryCount += 1
                stack.append(contentsOf: node.children)
                continue
            }
            result.fileCount += 1
            result.totalAllocatedSize += node.allocatedSize
            result.totalLogicalSize += node.logicalSize

            let key = node.fileExtension
            extensions[key, default: ExtensionStat(fileExtension: key)]
                .add(node)
            owners[node.ownerID, default: OwnerStat(ownerID: node.ownerID, name: "")]
                .add(node)
            let bucket = node.modificationDate.map {
                FileAgeBucket.bucket(forAgeInDays: now.timeIntervalSince($0) / 86_400)
            } ?? .unknown
            ages[bucket, default: AgeStat(bucket: bucket)].add(node)
            offer(node)
        }

        // The root itself was counted as a directory above; it is the
        // container, not an entry in it.
        result.directoryCount = max(0, result.directoryCount - 1)

        result.extensions = extensions.values.sorted { $0.allocatedSize > $1.allocatedSize }
        result.owners = owners.values
            .map { OwnerStat(
                ownerID: $0.ownerID,
                name: UserNames.displayName(for: $0.ownerID),
                fileCount: $0.fileCount,
                allocatedSize: $0.allocatedSize,
                logicalSize: $0.logicalSize
            ) }
            .sorted { $0.allocatedSize > $1.allocatedSize }
        result.ages = FileAgeBucket.allCases.compactMap { ages[$0] }
        candidates.sort { $0.allocatedSize > $1.allocatedSize }
        result.topFiles = candidates.prefix(topFileLimit).map(TopFile.init(node:))
        return result
    }
}

private extension ExtensionStat {
    mutating func add(_ node: FileNode) {
        fileCount += 1
        allocatedSize += node.allocatedSize
        logicalSize += node.logicalSize
    }
}

private extension OwnerStat {
    mutating func add(_ node: FileNode) {
        fileCount += 1
        allocatedSize += node.allocatedSize
        logicalSize += node.logicalSize
    }
}

private extension AgeStat {
    mutating func add(_ node: FileNode) {
        fileCount += 1
        allocatedSize += node.allocatedSize
        logicalSize += node.logicalSize
    }
}

/// uid → account name, resolved once per uid and cached: a scan has millions
/// of files and a handful of owners.
public enum UserNames {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Int32: String] = [:]

    public static func displayName(for ownerID: Int32?) -> String {
        guard let ownerID else { return "—" }
        return lock.withLock {
            if let cached = cache[ownerID] { return cached }
            var name = "#\(ownerID)"
            if let entry = getpwuid(uid_t(bitPattern: ownerID)) {
                let account = String(cString: entry.pointee.pw_name)
                if !account.isEmpty { name = account }
            }
            cache[ownerID] = name
            return name
        }
    }
}
