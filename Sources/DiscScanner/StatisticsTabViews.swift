import AppKit
import Charts
import SwiftUI
import DiscScannerCore

/// Shared frame for the four statistics tabs: they all need the same
/// "still counting" and "nothing here" states.
struct StatisticsContainer<Content: View>: View {
    let statistics: FileStatistics?
    let isComputing: Bool
    @ViewBuilder let content: (FileStatistics) -> Content

    var body: some View {
        if let statistics, !isComputing {
            content(statistics)
        } else if isComputing {
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(L("stats.computing"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(L("stats.empty"), systemImage: "chart.bar.doc.horizontal")
        }
    }
}

struct ExtensionsTabView: View {
    let statistics: FileStatistics?
    let isComputing: Bool
    @State private var sortOrder = [
        KeyPathComparator(\ExtensionStat.allocatedSize, order: .reverse),
    ]

    var body: some View {
        StatisticsContainer(statistics: statistics, isComputing: isComputing) { stats in
            Table(stats.extensions.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn(L("common.name"), value: \.fileExtension) { stat in
                    Text(stat.fileExtension.isEmpty ? L("ext.none") : "." + stat.fileExtension)
                }
                TableColumn(L("common.size"), value: \.allocatedSize) { stat in
                    Text(Format.bytes(stat.allocatedSize)).monospacedDigit()
                }
                .width(min: 90, ideal: 110)
                TableColumn(L("common.logicalSize"), value: \.logicalSize) { stat in
                    Text(Format.bytes(stat.logicalSize)).monospacedDigit()
                }
                .width(min: 90, ideal: 110)
                TableColumn(L("common.files"), value: \.fileCount) { stat in
                    Text(Format.count(stat.fileCount)).monospacedDigit()
                }
                .width(min: 70, ideal: 90)
            }
        }
    }
}

struct UsersTabView: View {
    let statistics: FileStatistics?
    let isComputing: Bool
    @State private var sortOrder = [
        KeyPathComparator(\OwnerStat.allocatedSize, order: .reverse),
    ]

    var body: some View {
        StatisticsContainer(statistics: statistics, isComputing: isComputing) { stats in
            Table(stats.owners.sorted(using: sortOrder), sortOrder: $sortOrder) {
                TableColumn(L("common.owner"), value: \.name) { stat in
                    Label(stat.name, systemImage: "person.crop.circle")
                }
                TableColumn(L("common.size"), value: \.allocatedSize) { stat in
                    Text(Format.bytes(stat.allocatedSize)).monospacedDigit()
                }
                .width(min: 90, ideal: 110)
                TableColumn(L("common.files"), value: \.fileCount) { stat in
                    Text(Format.count(stat.fileCount)).monospacedDigit()
                }
                .width(min: 70, ideal: 90)
            }
        }
    }
}

struct AgeTabView: View {
    let statistics: FileStatistics?
    let isComputing: Bool

    var body: some View {
        StatisticsContainer(statistics: statistics, isComputing: isComputing) { stats in
            VStack(spacing: 0) {
                Chart(stats.ages) { stat in
                    BarMark(
                        x: .value(L("common.age"), AgeTabView.name(for: stat.bucket)),
                        y: .value(L("common.size"), Double(stat.allocatedSize))
                    )
                    .cornerRadius(3)
                    .foregroundStyle(Color.accentColor.gradient)
                }
                .chartXScale(domain: stats.ages.map { AgeTabView.name(for: $0.bucket) })
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let bytes = value.as(Double.self) {
                                Text(Format.bytes(Int64(bytes)))
                            }
                        }
                    }
                }
                .frame(height: 180)
                .padding(12)
                Divider()
                Table(stats.ages) {
                    TableColumn(L("common.age")) { stat in
                        Text(AgeTabView.name(for: stat.bucket))
                    }
                    TableColumn(L("common.size")) { stat in
                        Text(Format.bytes(stat.allocatedSize)).monospacedDigit()
                    }
                    .width(min: 90, ideal: 110)
                    TableColumn(L("common.files")) { stat in
                        Text(Format.count(stat.fileCount)).monospacedDigit()
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn(L("common.share")) { stat in
                        Text(Format.percent(
                            stats.totalAllocatedSize > 0
                                ? Double(stat.allocatedSize) / Double(stats.totalAllocatedSize)
                                : 0
                        ))
                        .monospacedDigit()
                    }
                    .width(min: 70, ideal: 90)
                }
            }
        }
    }

    static func name(for bucket: FileAgeBucket) -> String {
        L("age.\(bucket.rawValue)")
    }
}

struct TopFilesTabView: View {
    let statistics: FileStatistics?
    let isComputing: Bool
    @State private var selection: Set<TopFile.ID> = []
    @State private var sortOrder = [
        KeyPathComparator(\TopFile.allocatedSize, order: .reverse),
    ]

    var body: some View {
        StatisticsContainer(statistics: statistics, isComputing: isComputing) { stats in
            Table(
                stats.topFiles.sorted(using: sortOrder),
                selection: $selection,
                sortOrder: $sortOrder
            ) {
                TableColumn(L("common.name"), value: \.name) { file in
                    Text(file.name).lineLimit(1).truncationMode(.middle)
                }
                TableColumn(L("common.size"), value: \.allocatedSize) { file in
                    Text(Format.bytes(file.allocatedSize)).monospacedDigit()
                }
                .width(min: 90, ideal: 110)
                TableColumn(L("common.modified"), value: \.sortDate) { file in
                    Text(Format.date(file.modificationDate)).monospacedDigit()
                }
                .width(min: 120, ideal: 150)
                TableColumn(L("common.path"), value: \.path) { file in
                    Text(file.path)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                        .help(file.path)
                }
            }
            .contextMenu(forSelectionType: TopFile.ID.self) { paths in
                Button(L("menu.showInFinder")) {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        paths.map { URL(fileURLWithPath: $0) }
                    )
                }
                .disabled(paths.isEmpty)
            }
        }
    }
}
