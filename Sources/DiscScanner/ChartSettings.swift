import Foundation
import DiscScannerCore

enum ChartStyle: String, Codable, CaseIterable, Identifiable {
    case pie
    case donut
    case bar

    var id: String { rawValue }
}

/// What the Chart tab draws and how. Persisted so a preferred view survives
/// a relaunch — the setting is about how someone reads a disk, and that does
/// not change between scans.
struct ChartSettings: Codable, Equatable {
    var sizeMode: SizeMode = .allocated
    var style: ChartStyle = .pie
    var maximumSlices = 8
    var groupLooseFiles = true
    var showFreeSpace = true
    var showPercentages = true

    static let slicesRange = 3...16

    private static let defaultsKey = "chartSettings"

    static func load(from defaults: UserDefaults = .standard) -> ChartSettings {
        guard
            let data = defaults.data(forKey: defaultsKey),
            var settings = try? JSONDecoder().decode(ChartSettings.self, from: data)
        else { return ChartSettings() }
        settings.maximumSlices = min(max(settings.maximumSlices, slicesRange.lowerBound), slicesRange.upperBound)
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    func sliceOptions(freeSpace: Int64?) -> ChartSliceOptions {
        ChartSliceOptions(
            sizeMode: sizeMode,
            maximumSlices: maximumSlices,
            groupLooseFiles: groupLooseFiles,
            freeSpace: showFreeSpace ? freeSpace : nil
        )
    }
}
