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
}
