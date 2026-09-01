import Foundation
import Observation
import DiscScannerCore

/// Result of one file-store operation, reduced to something that can cross
/// actor boundaries: the value, or the message to show. Errors themselves
/// carry no Sendable guarantee.
enum StoreOutcome<Value: Sendable>: Sendable {
    case success(Value)
    case failure(String)

    init(_ body: () throws -> Value) {
        do {
            self = .success(try body())
        } catch {
            self = .failure(error.localizedDescription)
        }
    }
}

/// What a finished comparison hands back to the UI.
struct ComparisonOutcome: Sendable {
    let result: ComparisonReport
    let baselineLabel: String
    let targetLabel: String
}

@MainActor
@Observable
final class AppState {
    enum Tab: String, CaseIterable, Identifiable {
        case chart
        case details
        case treemap
        case fileExtensions
        case users
        case age
        case topFiles
        case history

        var id: String { rawValue }
    }

    /// What the History tab compares the baseline against.
    enum ComparisonTarget: Hashable {
        case currentScan
        case saved(UUID)
    }

    var root: FileNode?
    var progress = ScanProgress()
    var isScanning = false
    /// Starts on the tree: it is the first thing to look at once a scan
    /// finishes, and the tab bar only appears then anyway.
    var tab: Tab = .details
    /// Set from the empty state: the history is the one view worth showing
    /// before a scan exists, because opening a saved one is how you get a
    /// scan without waiting for the disk.
    var isShowingSavedScans = false
    var selection: Set<String> = []
    var treemapZoomPath: String?
    var pendingDeletePaths: [String] = []
    var showDeleteDialog = false
    var deletionFailures: [DeletionFailure] = []
    var showFailureAlert = false
    var scanStartDate: Date?
    var expectedTotalBytes: Int64?
    var accessBannerDismissed = false

    /// Volume figures of the scanned root, nil for an ordinary folder — a
    /// "free space" wedge only means something for a whole volume.
    var volumeFreeSpace: Int64?
    var volumeTotalCapacity: Int64?
    var scannedRootURL: URL?

    var chartSettings = ChartSettings.load()
    /// Directory the chart is drilled into; nil is the scan root.
    var chartPath: String?
    /// Directory the details table is browsing; nil is the scan root.
    var detailsPath: String?

    var statistics: FileStatistics?
    var isComputingStatistics = false

    var updateOutcome: UpdateCheck.Outcome?
    var isCheckingForUpdates = false
    /// Text for the update alert — only a manual check reports back; the one
    /// at launch stays quiet unless it has something to offer.
    var updateMessage: String?
    var updateBannerDismissed = false

    var savedScans: [ScanStore.Entry] = []
    var isSavingScan = false
    var storeError: String?
    var comparisonBaseline: UUID?
    var comparisonTarget: ComparisonTarget = .currentScan
    var comparison: ComparisonReport?
    var comparisonLabels: (baseline: String, target: String)?
    var isComparing = false

    private var scanTask: Task<Void, Never>?
    private var statisticsTask: Task<Void, Never>?
    private var scanGeneration = UUID()

    func startScan(url: URL) {
        cancelScan()
        root = nil
        selection = []
        treemapZoomPath = nil
        chartPath = nil
        detailsPath = nil
        statistics = nil
        comparison = nil
        isShowingSavedScans = false
        progress = ScanProgress()
        isScanning = true
        scanStartDate = Date()
        scannedRootURL = url
        let volume = Self.volumeInfo(for: url)
        volumeFreeSpace = volume.free
        volumeTotalCapacity = volume.total
        expectedTotalBytes = volume.used
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
                    self.refreshStatistics()
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

    /// Volume figures for the scanned URL. Free space and capacity are only
    /// reported when the URL *is* the volume root, and `used` (the scan's
    /// expected total) with it — a folder's total is not predictable without
    /// a pre-scan that would cost as much as the scan itself.
    private static func volumeInfo(for url: URL) -> (free: Int64?, total: Int64?, used: Int64?) {
        let keys: Set<URLResourceKey> = [
            .volumeURLKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        ]
        guard
            let values = try? url.resourceValues(forKeys: keys),
            let volumeURL = values.volume,
            volumeURL.standardizedFileURL.path == url.standardizedFileURL.path,
            let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacity
        else { return (nil, nil, nil) }
        let used = total > available ? Int64(total - available) : nil
        return (Int64(available), Int64(total), used)
    }

    // MARK: - Statistics

    /// Recomputes the Extensions / Users / Age / Top-files tables off the
    /// main actor. A volume tree has millions of nodes; walking it on the
    /// main thread would freeze the window for seconds.
    func refreshStatistics() {
        statisticsTask?.cancel()
        guard let root, !isScanning else {
            statistics = nil
            isComputingStatistics = false
            return
        }
        isComputingStatistics = true
        statisticsTask = Task { [weak self] in
            let computed = await Task.detached(priority: .userInitiated) {
                FileStatistics.compute(root: root)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.statistics = computed
            self.isComputingStatistics = false
        }
    }

    // MARK: - Chart

    /// The directory the chart currently shows.
    var chartNode: FileNode? {
        guard let root else { return nil }
        guard let chartPath else { return root }
        return root.find(path: chartPath) ?? root
    }

    var chartSlices: [ChartSlice] {
        guard let node = chartNode else { return [] }
        // Free space belongs to the volume, not to a subfolder of it.
        let freeSpace = node.path == root?.path ? volumeFreeSpace : nil
        return ChartSlices.make(for: node, options: chartSettings.sliceOptions(freeSpace: freeSpace))
    }

    func drillIntoChart(path: String) {
        guard root?.find(path: path)?.isDirectory == true else { return }
        chartPath = path
    }

    /// The scan root down to `path`, for a breadcrumb bar. Walks by matching
    /// path prefixes rather than by splitting the string: a name may contain
    /// a surprise, the tree may not.
    func breadcrumb(to path: String?) -> [FileNode] {
        guard let root else { return [] }
        var trail: [FileNode] = [root]
        guard let path, path != root.path else { return trail }
        var node = root
        while let next = node.children.first(where: {
            path == $0.path || path.hasPrefix($0.path + "/")
        }) {
            trail.append(next)
            if next.path == path { break }
            node = next
        }
        return trail
    }

    /// The folder the details table is browsing, falling back to the root
    /// when the path is gone — a deletion can take it away underneath us.
    var detailsNode: FileNode? {
        guard let root else { return nil }
        guard let detailsPath else { return root }
        return root.find(path: detailsPath) ?? root
    }

    /// Moves the details table into `node`, or back to the root for it.
    func browseDetails(to node: FileNode) {
        detailsPath = node.path == root?.path ? nil : node.path
        selection = []
    }

    func persistChartSettings() {
        chartSettings.save()
    }

    // MARK: - Saved scans

    func refreshSavedScans() {
        Task { [weak self] in
            let outcome = await Task.detached(priority: .utility) {
                StoreOutcome { try ScanStore.list() }
            }.value
            guard let self else { return }
            switch outcome {
            case .success(let entries):
                self.savedScans = entries
                if let baseline = self.comparisonBaseline,
                   !entries.contains(where: { $0.id == baseline }) {
                    self.comparisonBaseline = nil
                }
            case .failure(let message):
                self.storeError = message
            }
        }
    }

    func saveCurrentScan() {
        guard let root, !isScanning, !isSavingScan else { return }
        isSavingScan = true
        let snapshot = ScanSnapshot(
            root: root,
            displayName: displayName(for: root),
            accessDeniedCount: progress.accessDeniedCount,
            volumeFreeSpace: volumeFreeSpace,
            volumeTotalCapacity: volumeTotalCapacity,
            statistics: statistics
        )
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                StoreOutcome { try ScanStore.save(snapshot) }
            }.value
            guard let self else { return }
            self.isSavingScan = false
            switch outcome {
            case .success:
                self.refreshSavedScans()
            case .failure(let message):
                self.storeError = message
            }
        }
    }

    func openSaved(_ entry: ScanStore.Entry) {
        cancelScan()
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                StoreOutcome { try ScanStore.read(at: entry.url) }
            }.value
            guard let self else { return }
            switch outcome {
            case .success(let snapshot):
                self.root = snapshot.root
                self.selection = []
                self.treemapZoomPath = nil
                self.chartPath = nil
                self.detailsPath = nil
                self.comparison = nil
                self.scannedRootURL = nil
                self.volumeFreeSpace = snapshot.summary.volumeFreeSpace
                self.volumeTotalCapacity = snapshot.summary.volumeTotalCapacity
                self.progress = Self.progress(from: snapshot.summary)
                self.refreshStatistics()
            case .failure(let message):
                self.storeError = message
            }
        }
    }

    func deleteSaved(_ entry: ScanStore.Entry) {
        Task { [weak self] in
            let outcome = await Task.detached(priority: .utility) {
                StoreOutcome { try ScanStore.delete(at: entry.url) }
            }.value
            guard let self else { return }
            if case .failure(let message) = outcome {
                self.storeError = message
                return
            }
            if self.comparisonBaseline == entry.id { self.comparisonBaseline = nil }
            if self.comparisonTarget == .saved(entry.id) { self.comparisonTarget = .currentScan }
            self.refreshSavedScans()
        }
    }

    /// The status bar reads from `progress`, so a loaded scan fills it in
    /// with what the saved summary recorded.
    private static func progress(from summary: ScanSnapshotSummary) -> ScanProgress {
        var progress = ScanProgress()
        progress.filesScanned = summary.fileCount
        progress.directoriesScanned = summary.directoryCount
        progress.totalBytes = summary.totalAllocatedSize
        progress.accessDeniedCount = summary.accessDeniedCount
        return progress
    }

    private func displayName(for root: FileNode) -> String {
        // A scanned volume goes by its volume name ("Macintosh HD"), a folder
        // by its own — "/" as a display name helps nobody.
        if let url = scannedRootURL,
           let values = try? url.resourceValues(forKeys: [.volumeLocalizedNameKey, .volumeURLKey]),
           let name = values.volumeLocalizedName,
           values.volume?.standardizedFileURL.path == url.standardizedFileURL.path {
            return name
        }
        return root.name.isEmpty ? root.path : root.name
    }

    // MARK: - Comparison

    var canCompare: Bool {
        guard comparisonBaseline != nil else { return false }
        switch comparisonTarget {
        case .currentScan: return root != nil && !isScanning
        case .saved(let id): return id != comparisonBaseline
        }
    }

    func runComparison() {
        guard let baselineID = comparisonBaseline,
              let baselineEntry = savedScans.first(where: { $0.id == baselineID }),
              canCompare, !isComparing
        else { return }

        let targetEntry: ScanStore.Entry?
        switch comparisonTarget {
        case .currentScan:
            targetEntry = nil
        case .saved(let id):
            guard let entry = savedScans.first(where: { $0.id == id }) else { return }
            targetEntry = entry
        }

        let liveRoot = root
        let sizeMode = chartSettings.sizeMode
        isComparing = true
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                StoreOutcome { () -> ComparisonOutcome in
                    let baseline = try ScanStore.read(at: baselineEntry.url)
                    let current: FileNode
                    let targetLabel: String
                    if let targetEntry {
                        let snapshot = try ScanStore.read(at: targetEntry.url)
                        current = snapshot.root
                        targetLabel = snapshot.summary.displayName
                    } else if let liveRoot {
                        current = liveRoot
                        targetLabel = liveRoot.name
                    } else {
                        throw ScanStore.StoreError.malformedFile(baselineEntry.url.path)
                    }
                    let comparison = SnapshotComparison.compare(
                        baseline: baseline.root,
                        current: current,
                        options: ComparisonOptions(sizeMode: sizeMode)
                    )
                    return ComparisonOutcome(
                        result: comparison,
                        baselineLabel: baseline.summary.displayName,
                        targetLabel: targetLabel
                    )
                }
            }.value
            guard let self else { return }
            self.isComparing = false
            switch outcome {
            case .success(let value):
                self.comparison = value.result
                self.comparisonLabels = (value.baselineLabel, value.targetLabel)
            case .failure(let message):
                self.storeError = message
            }
        }
    }

    // MARK: - Updates

    /// Repository the release check asks about.
    static let repositoryOwner = "NoiXdev"
    static let repositoryName = "DiscScanner"

    private static let lastCheckKey = "lastUpdateCheck"
    private static let dismissedTagKey = "dismissedUpdateTag"
    private static let automaticChecksKey = "automaticUpdateChecks"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    /// What the app reports itself as; nil when it runs without a bundle,
    /// which is what `swift run` does.
    var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// `force` is a manual check: it ignores the once-a-day limit, the
    /// opt-out, and a banner dismissed for this version, and it always
    /// reports back — that is the difference between asking and being told.
    func checkForUpdates(force: Bool) {
        guard !isCheckingForUpdates else { return }
        let defaults = UserDefaults.standard
        if !force {
            if defaults.object(forKey: Self.automaticChecksKey) != nil,
               !defaults.bool(forKey: Self.automaticChecksKey) {
                return
            }
            if let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
               Date().timeIntervalSince(last) < Self.checkInterval {
                return
            }
        }

        let version = currentVersion
        let userAgent = "DiscScanner/\(version ?? "dev") (+https://github.com/\(Self.repositoryOwner)/\(Self.repositoryName))"
        isCheckingForUpdates = true
        Task { [weak self] in
            defer { self?.isCheckingForUpdates = false }
            do {
                let release = try await UpdateCheck.fetchLatestRelease(
                    owner: Self.repositoryOwner,
                    repo: Self.repositoryName,
                    userAgent: userAgent
                )
                guard let self else { return }
                UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
                let outcome = UpdateCheck.evaluate(
                    release: release,
                    currentVersion: version ?? ""
                )
                self.apply(outcome, manual: force)
            } catch {
                guard let self, force else { return }
                self.updateMessage = Self.message(for: error)
            }
        }
    }

    private func apply(_ outcome: UpdateCheck.Outcome, manual: Bool) {
        let defaults = UserDefaults.standard
        updateOutcome = outcome
        switch outcome {
        case .updateAvailable(let release):
            let dismissed = defaults.string(forKey: Self.dismissedTagKey)
            updateBannerDismissed = !manual && dismissed == release.tagName
            if manual { defaults.removeObject(forKey: Self.dismissedTagKey) }
        case .upToDate(let release):
            updateBannerDismissed = true
            if manual { updateMessage = L("update.upToDate", release.displayName) }
        case .unknownVersion:
            updateBannerDismissed = true
            if manual { updateMessage = L("update.unknownVersion") }
        }
    }

    /// Keeps the banner away for this release, this time for good.
    func dismissUpdateBanner() {
        if case .updateAvailable(let release) = updateOutcome {
            UserDefaults.standard.set(release.tagName, forKey: Self.dismissedTagKey)
        }
        updateBannerDismissed = true
    }

    private static func message(for error: Error) -> String {
        switch error {
        case UpdateCheckError.rateLimited:
            return L("update.error.rateLimited")
        case UpdateCheckError.notFound:
            return L("update.error.notFound")
        case UpdateCheckError.invalidRepository, UpdateCheckError.invalidResponse:
            return L("update.error.response")
        case UpdateCheckError.badStatus(let code):
            return L("update.error.status", String(code))
        default:
            return L("update.error.network", error.localizedDescription)
        }
    }

    // MARK: - Deletion

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
            refreshStatistics()
        }
        selection = []
        deletionFailures = result.failures
        showFailureAlert = !result.failures.isEmpty
    }
}
