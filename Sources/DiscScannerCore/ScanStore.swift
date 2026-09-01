import Foundation

/// Reads and writes `.dscan` files and manages the folder they live in.
///
/// File layout, one scan per file:
///
///     <summary JSON on a single line>\n
///     <LZFSE-compressed JSON of the tree>
///
/// The header is plain text so listing the history only has to read the
/// first few hundred bytes of each file; the tree behind it compresses to a
/// fraction of its JSON size, which matters when a volume scan serialises
/// millions of nodes.
public enum ScanStore {
    public static let fileExtension = "dscan"

    public enum StoreError: Error, LocalizedError, Equatable {
        case malformedFile(String)

        public var errorDescription: String? {
            switch self {
            case .malformedFile(let path):
                return "Not a readable DiscScanner scan: \(path)"
            }
        }
    }

    /// One entry of the history list: where it is, and what is in it.
    public struct Entry: Identifiable, Sendable, Equatable {
        public let url: URL
        public let summary: ScanSnapshotSummary

        public var id: UUID { summary.id }

        public init(url: URL, summary: ScanSnapshotSummary) {
            self.url = url
            self.summary = summary
        }
    }

    /// `~/Library/Application Support/DiscScanner/Scans`, created on demand.
    public static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base
            .appendingPathComponent("DiscScanner", isDirectory: true)
            .appendingPathComponent("Scans", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func write(_ snapshot: ScanSnapshot, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        var data = try encoder.encode(snapshot.summary)
        // The header must stay on one line — it is the record separator.
        guard !data.contains(0x0A) else {
            throw StoreError.malformedFile(url.path)
        }
        data.append(0x0A)
        let tree = try encoder.encode(snapshot.root)
        data.append(compress(tree))
        try data.write(to: url, options: .atomic)
    }

    /// Writes into the default directory under a stable, sortable name.
    @discardableResult
    public static func save(
        _ snapshot: ScanSnapshot,
        in directory: URL? = nil
    ) throws -> Entry {
        let directory = try directory ?? defaultDirectory()
        let base = fileName(for: snapshot.summary)
        var url = directory.appendingPathComponent("\(base).\(fileExtension)")
        if FileManager.default.fileExists(atPath: url.path) {
            // Two scans in the same second: keep both.
            let suffix = snapshot.summary.id.uuidString.prefix(8)
            url = directory.appendingPathComponent("\(base)-\(suffix).\(fileExtension)")
        }
        try write(snapshot, to: url)
        return Entry(url: url, summary: snapshot.summary)
    }

    public static func readSummary(at url: URL) throws -> ScanSnapshotSummary {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // 64 KiB is far more than a header needs and far less than a tree.
        let head = try handle.read(upToCount: 64 * 1024) ?? Data()
        guard let newline = head.firstIndex(of: 0x0A) else {
            throw StoreError.malformedFile(url.path)
        }
        return try decoder().decode(ScanSnapshotSummary.self, from: Data(head[..<newline]))
    }

    public static func read(at url: URL) throws -> ScanSnapshot {
        let data = try Data(contentsOf: url)
        guard let newline = data.firstIndex(of: 0x0A) else {
            throw StoreError.malformedFile(url.path)
        }
        let decoder = decoder()
        let summary = try decoder.decode(ScanSnapshotSummary.self, from: Data(data[..<newline]))
        let payload = data[data.index(after: newline)...]
        let root = try decoder.decode(FileNode.self, from: decompress(Data(payload)))
        return ScanSnapshot(summary: summary, root: root)
    }

    /// Every readable scan in the directory, newest first. Unreadable files
    /// are skipped rather than failing the whole listing — one corrupt file
    /// must not hide the rest of the history.
    public static func list(in directory: URL? = nil) throws -> [Entry] {
        let directory = try directory ?? defaultDirectory()
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { $0.pathExtension == fileExtension }
            .compactMap { url in
                (try? readSummary(at: url)).map { Entry(url: url, summary: $0) }
            }
            .sorted { $0.summary.createdAt > $1.summary.createdAt }
    }

    public static func delete(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    /// `2026-09-01-083012-Macintosh-HD` — sorts chronologically in Finder and
    /// still says what it is.
    static func fileName(for summary: ScanSnapshotSummary) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = formatter.string(from: summary.createdAt)
        let name = summary.displayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return name.isEmpty ? stamp : "\(stamp)-\(name)"
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    /// LZFSE, with the uncompressed JSON as the fallback: a scan that cannot
    /// be compressed is still a scan worth keeping.
    private static func compress(_ data: Data) -> Data {
        guard let compressed = try? (data as NSData).compressed(using: .lzfse) else {
            return data
        }
        return Data(referencing: compressed)
    }

    private static func decompress(_ data: Data) throws -> Data {
        if let plain = try? (data as NSData).decompressed(using: .lzfse) {
            return Data(referencing: plain)
        }
        return data
    }
}
