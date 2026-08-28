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

    private var scanTask: Task<Void, Never>?

    func startScan(url: URL) {
        cancelScan()
        root = nil
        selection = []
        treemapZoomPath = nil
        progress = ScanProgress()
        isScanning = true
        let scanner = DiskScanner()
        scanTask = Task { [weak self] in
            for await event in scanner.scan(url: url) {
                guard let self else { return }
                switch event {
                case .progress(let progress):
                    self.progress = progress
                case .snapshot(let tree):
                    self.root = tree
                case .finished(let tree):
                    self.root = tree
                    self.isScanning = false
                }
            }
            self?.isScanning = false
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
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
