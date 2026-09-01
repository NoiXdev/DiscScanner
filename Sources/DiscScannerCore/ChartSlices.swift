import Foundation

/// One wedge of the chart. Directories keep their path so the view can drill
/// into them; the aggregate wedges have none.
public struct ChartSlice: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case directory
        case file
        /// All loose files of the folder, rolled into one wedge.
        case looseFiles
        /// Everything below the slice limit.
        case others
        case freeSpace
    }

    public let id: String
    public let name: String
    public let path: String?
    public let size: Int64
    public let kind: Kind
    /// Share of the chart total, 0…1.
    public let fraction: Double
    /// Number of items behind an aggregate wedge, 0 for a single entry.
    public let itemCount: Int

    public init(
        id: String,
        name: String,
        path: String?,
        size: Int64,
        kind: Kind,
        fraction: Double,
        itemCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.size = size
        self.kind = kind
        self.fraction = fraction
        self.itemCount = itemCount
    }
}

public struct ChartSliceOptions: Sendable, Equatable {
    public var sizeMode: SizeMode
    /// Wedges before the remainder is folded into "Others".
    public var maximumSlices: Int
    /// Roll the folder's own files into a single wedge, the way a
    /// disk-usage chart stays readable in a folder with 4000 loose files.
    public var groupLooseFiles: Bool
    /// Added as its own wedge when set, so the chart shows the whole volume.
    public var freeSpace: Int64?

    public init(
        sizeMode: SizeMode = .allocated,
        maximumSlices: Int = 8,
        groupLooseFiles: Bool = true,
        freeSpace: Int64? = nil
    ) {
        self.sizeMode = sizeMode
        self.maximumSlices = maximumSlices
        self.groupLooseFiles = groupLooseFiles
        self.freeSpace = freeSpace
    }
}

public enum ChartSlices {
    /// Wedges for one directory's children, largest first, with the tail
    /// folded into "Others" and free space appended last.
    public static func make(
        for node: FileNode,
        options: ChartSliceOptions = ChartSliceOptions()
    ) -> [ChartSlice] {
        var entries: [(name: String, path: String?, size: Int64, kind: ChartSlice.Kind, count: Int)] = []

        if options.groupLooseFiles {
            let files = node.children.filter { !$0.isDirectory }
            let loose = files.reduce(Int64(0)) { $0 + $1.size(options.sizeMode) }
            for directory in node.children where directory.isDirectory {
                entries.append((
                    directory.name, directory.path, directory.size(options.sizeMode), .directory, 0
                ))
            }
            if let only = files.first, files.count == 1 {
                // One file needs no rolling up — show it by name.
                entries.append((only.name, only.path, loose, .file, 0))
            } else if !files.isEmpty {
                entries.append(("", nil, loose, .looseFiles, files.count))
            }
        } else {
            for child in node.children {
                entries.append((
                    child.name,
                    child.path,
                    child.size(options.sizeMode),
                    child.isDirectory ? .directory : .file,
                    0
                ))
            }
        }

        entries.sort { $0.size > $1.size }

        var kept = entries
        var others: (size: Int64, count: Int)?
        let limit = max(1, options.maximumSlices)
        if entries.count > limit {
            kept = Array(entries.prefix(limit))
            let rest = entries.dropFirst(limit)
            others = (rest.reduce(Int64(0)) { $0 + $1.size }, rest.count)
        }

        var total = kept.reduce(Int64(0)) { $0 + $1.size } + (others?.size ?? 0)
        if let freeSpace = options.freeSpace { total += freeSpace }
        let denominator = Double(max(total, 1))

        var slices = kept.map { entry in
            ChartSlice(
                id: entry.path ?? "loose-files",
                name: entry.name,
                path: entry.path,
                size: entry.size,
                kind: entry.kind,
                fraction: Double(entry.size) / denominator,
                itemCount: entry.count
            )
        }
        if let others {
            slices.append(ChartSlice(
                id: "others",
                name: "",
                path: nil,
                size: others.size,
                kind: .others,
                fraction: Double(others.size) / denominator,
                itemCount: others.count
            ))
        }
        if let freeSpace = options.freeSpace {
            slices.append(ChartSlice(
                id: "free-space",
                name: "",
                path: nil,
                size: freeSpace,
                kind: .freeSpace,
                fraction: Double(freeSpace) / denominator
            ))
        }
        return slices
    }
}
