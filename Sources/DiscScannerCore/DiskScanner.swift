import Foundation

public final class DiskScanner: @unchecked Sendable {
    let state = ScanState()

    public init() {}

    public func cancel() {
        state.cancel()
    }

    /// Starts a scan and returns a stream of batched events. A timer flushes
    /// progress + a snapshot tree every `interval`; live snapshots are
    /// depth-capped to `liveSnapshotDepth` levels (nil = full) so huge trees
    /// do not stall the scan workers or the consumer. On completion the
    /// stream emits one final `.progress` followed by exactly one
    /// `.finished` with the exact, uncapped final tree, then completes.
    /// Terminating the stream (e.g. by cancelling the consuming task)
    /// cancels the scan.
    public func scan(
        url: URL,
        interval: TimeInterval = 0.4,
        liveSnapshotDepth: Int? = 8
    ) -> AsyncStream<ScanEvent> {
        let state = self.state
        return AsyncStream(bufferingPolicy: .bufferingNewest(16)) { continuation in
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + interval, repeating: interval)
            timer.setEventHandler {
                guard !state.isFinished else { return }
                continuation.yield(.progress(state.progressSnapshot()))
                if let tree = state.treeSnapshot(maxDepth: liveSnapshotDepth) {
                    continuation.yield(.snapshot(tree))
                }
            }
            timer.resume()

            DispatchQueue.global(qos: .userInitiated).async {
                let finalTree = Self.performScan(url: url, state: state)
                timer.cancel()
                continuation.yield(.progress(state.progressSnapshot()))
                continuation.yield(.finished(finalTree))
                continuation.finish()
            }

            continuation.onTermination = { _ in
                state.cancel()
            }
        }
    }

    // Prefetched for every directory entry. The size, date and owner keys
    // feed the Extensions / Users / Age-of-files statistics; asking for them
    // here costs one batched lookup instead of a stat() per file later.
    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .totalFileSizeKey, .fileSizeKey, .contentModificationDateKey, .fileOwnerAccountIDKey,
    ]

    /// Blocking parallel scan. Returns the final (or partial, if cancelled)
    /// snapshot tree. Runs directories as work items on a concurrent queue.
    static func performScan(url: URL, state: ScanState) -> FileNode {
        let root = MutableNode(
            name: url.lastPathComponent,
            path: url.standardizedFileURL.path,
            isDirectory: true,
            parent: nil
        )
        state.setRoot(root)
        let queue = DispatchQueue(
            label: "DiscScanner.traversal",
            qos: .userInitiated,
            attributes: .concurrent
        )
        let group = DispatchGroup()
        scanDirectory(root, state: state, queue: queue, group: group)
        group.wait()
        state.markFinished()
        return state.treeSnapshot() ?? root.snapshot()
    }

    private static func scanDirectory(
        _ node: MutableNode,
        state: ScanState,
        queue: DispatchQueue,
        group: DispatchGroup
    ) {
        group.enter()
        queue.async {
            defer { group.leave() }
            guard !state.isCancelled else { return }

            let url = URL(fileURLWithPath: node.path, isDirectory: true)
            let entries: [URL]
            do {
                entries = try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: resourceKeys,
                    options: []
                )
            } catch {
                state.mutate { progress in
                    node.isAccessDenied = true
                    progress.accessDeniedCount += 1
                }
                return
            }

            var subdirectories: [MutableNode] = []
            state.mutate { progress in
                progress.directoriesScanned += 1
                progress.currentPath = node.path
                for entry in entries {
                    let values = try? entry.resourceValues(forKeys: Set(resourceKeys))
                    let isSymlink = values?.isSymbolicLink ?? false
                    let isDirectory = !isSymlink && (values?.isDirectory ?? false)
                    let child = MutableNode(
                        name: entry.lastPathComponent,
                        path: entry.standardizedFileURL.path,
                        isDirectory: isDirectory,
                        parent: node
                    )
                    node.children.append(child)
                    if isDirectory {
                        subdirectories.append(child)
                    } else {
                        let size = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
                        let logical = Int64(values?.totalFileSize ?? values?.fileSize ?? 0)
                        child.allocatedSize = size
                        child.logicalSize = logical
                        child.modificationDate = values?.contentModificationDate
                        child.ownerID = Self.ownerID(from: values)
                        progress.filesScanned += 1
                        progress.totalBytes += size
                        var ancestor: MutableNode? = node
                        while let current = ancestor {
                            current.allocatedSize += size
                            current.logicalSize += logical
                            ancestor = current.parent
                        }
                    }
                }
            }
            for subdirectory in subdirectories {
                scanDirectory(subdirectory, state: state, queue: queue, group: group)
            }
        }
    }

    /// URLResourceValues has no typed accessor for the owner, so it comes out
    /// of the untyped bag — still from the same prefetched batch.
    private static func ownerID(from values: URLResourceValues?) -> Int32? {
        (values?.allValues[.fileOwnerAccountIDKey] as? NSNumber)?.int32Value
    }
}
