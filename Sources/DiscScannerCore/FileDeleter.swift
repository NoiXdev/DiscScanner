import Foundation

public enum DeletionMethod: Sendable {
    case trash
    case permanent
}

public struct DeletionFailure: Sendable, Equatable {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

public struct DeletionResult: Sendable {
    public let deletedPaths: [String]
    public let failures: [DeletionFailure]

    public init(deletedPaths: [String], failures: [DeletionFailure]) {
        self.deletedPaths = deletedPaths
        self.failures = failures
    }
}

public enum FileDeleter {
    /// Deletes each path independently; one failure never aborts the rest.
    /// Callers are expected to pass pre-pruned, non-overlapping paths; see `pruneRedundant`.
    public static func delete(paths: [String], method: DeletionMethod) -> DeletionResult {
        var deleted: [String] = []
        var failures: [DeletionFailure] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            do {
                switch method {
                case .trash:
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                case .permanent:
                    try FileManager.default.removeItem(at: url)
                }
                deleted.append(path)
            } catch {
                failures.append(DeletionFailure(path: path, message: error.localizedDescription))
            }
        }
        return DeletionResult(deletedPaths: deleted, failures: failures)
    }

    /// Drops paths that are descendants of another selected path, so deleting
    /// a folder plus a file inside it never double-deletes.
    public static func pruneRedundant(_ paths: Set<String>) -> [String] {
        paths.filter { path in
            !paths.contains { other in
                other != path && {
                    let prefix = other.hasSuffix("/") ? other : other + "/"
                    return path.hasPrefix(prefix)
                }()
            }
        }
        .sorted()
    }
}
