import Foundation

/// Shared mutable state of one scan run. A single lock guards both the
/// progress counters and the MutableNode tree; workers take it briefly per
/// directory, snapshots take it for the duration of the copy.
final class ScanState: @unchecked Sendable {
    private let lock = NSLock()
    private var progress = ScanProgress()
    private var root: MutableNode?
    private var cancelled = false
    private var finished = false

    func setRoot(_ node: MutableNode) {
        lock.withLock { root = node }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func markFinished() {
        lock.withLock { finished = true }
    }

    var isFinished: Bool {
        lock.withLock { finished }
    }

    /// Runs `body` with the lock held. Tree mutation must happen inside.
    func mutate<T>(_ body: (inout ScanProgress) -> T) -> T {
        lock.withLock { body(&progress) }
    }

    func progressSnapshot() -> ScanProgress {
        lock.withLock { progress }
    }

    func treeSnapshot(maxDepth: Int? = nil) -> FileNode? {
        lock.withLock { root?.snapshot(maxDepth: maxDepth) }
    }
}
