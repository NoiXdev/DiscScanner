import Foundation
import Observation
import DiscScannerCore

@MainActor
@Observable
final class AppState {
    enum ViewMode: String, CaseIterable, Identifiable {
        case list
        case treemap

        var id: String { rawValue }
    }

    var root: FileNode?
    var progress = ScanProgress()
    var isScanning = false
    var viewMode: ViewMode = .list
    var selection: Set<String> = []
    var treemapZoomPath: String?
    var pendingDeletePaths: [String] = []
    var showDeleteDialog = false
    var deletionFailures: [DeletionFailure] = []
    var showFailureAlert = false
    var scanStartDate: Date?
    var expectedTotalBytes: Int64?
    var accessBannerDismissed = false

    private var scanTask: Task<Void, Never>?
    private var scanGeneration = UUID()

    func startScan(url: URL) {
        cancelScan()
        root = nil
        selection = []
        treemapZoomPath = nil
        progress = ScanProgress()
        isScanning = true
        scanStartDate = Date()
        expectedTotalBytes = Self.volumeUsedBytes(for: url)
        accessBannerDismissed = false
        let generation = UUID()
        scanGeneration = generation
        let scanner = DiskScanner()
        scanTask = Task { [weak self] in
            for await event in scanner.scan(url: url) {
                guard let self, self.scanGeneration == generation else { return }
                switch event {
                case .progress(let progress):
                    self.progress = progress
                case .snapshot(let tree):
                    self.root = tree
                case .finished(let tree):
                    self.root = tree
                    self.isScanning = false
                    self.scanStartDate = nil
                }
            }
            guard let self, self.scanGeneration == generation else { return }
            self.isScanning = false
            self.scanStartDate = nil
        }
    }

    func cancelScan() {
        scanGeneration = UUID()
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scanStartDate = nil
    }

    /// Estimated total for a volume-root scan (used bytes of that volume);
    /// nil for ordinary folders, where the total is not predictable without
    /// a pre-scan that would cost as much as the scan itself.
    private static func volumeUsedBytes(for url: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [
            .volumeURLKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        ]
        guard
            let values = try? url.resourceValues(forKeys: keys),
            let volumeURL = values.volume,
            volumeURL.standardizedFileURL.path == url.standardizedFileURL.path,
            let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacity,
            total > available
        else { return nil }
        return Int64(total - available)
    }

    var pendingDeleteSize: Int64 {
        guard let root else { return 0 }
        return pendingDeletePaths
            .compactMap { root.find(path: $0)?.allocatedSize }
            .reduce(0, +)
    }

    func requestDelete(paths: Set<String>) {
        guard !paths.isEmpty, !isScanning else { return }
        pendingDeletePaths = FileDeleter.pruneRedundant(paths)
        showDeleteDialog = true
    }

    func performDelete(method: DeletionMethod) {
        let paths = pendingDeletePaths
        pendingDeletePaths = []
        guard !paths.isEmpty else { return }
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                FileDeleter.delete(paths: paths, method: method)
            }.value
            applyDeletionResult(result)
        }
    }

    private func applyDeletionResult(_ result: DeletionResult) {
        if let root, !result.deletedPaths.isEmpty {
            self.root = TreePruner.removing(paths: Set(result.deletedPaths), from: root)
        }
        selection = []
        deletionFailures = result.failures
        showFailureAlert = !result.failures.isEmpty
    }
}
