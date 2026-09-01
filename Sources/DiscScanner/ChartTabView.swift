import Charts
import SwiftUI
import DiscScannerCore

/// The Chart tab: one folder's children as a pie, donut or bar, with a
/// legend that doubles as the way to drill into a folder.
struct ChartTabView: View {
    @Bindable var appState: AppState

    private var slices: [ChartSlice] { appState.chartSlices }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if slices.isEmpty {
                ContentUnavailableView(L("chart.empty"), systemImage: "chart.pie")
            } else {
                HStack(alignment: .top, spacing: 20) {
                    chart
                        .frame(minWidth: 240, minHeight: 240)
                    legend
                        .frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
                }
                .padding(16)
            }
        }
        .onChange(of: appState.chartSettings) {
            appState.persistChartSettings()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            BreadcrumbBar(trail: appState.breadcrumb(to: appState.chartPath)) { node in
                appState.chartPath = node.path == appState.root?.path ? nil : node.path
            }
            Spacer(minLength: 12)
            Text(Format.bytes(appState.chartNode?.size(appState.chartSettings.sizeMode) ?? 0))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            settingsMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var settingsMenu: some View {
        Menu {
            Picker(L("chart.sizeMode"), selection: $appState.chartSettings.sizeMode) {
                Text(L("chart.size.allocated")).tag(SizeMode.allocated)
                Text(L("chart.size.logical")).tag(SizeMode.logical)
            }
            Picker(L("chart.style"), selection: $appState.chartSettings.style) {
                Text(L("chart.style.pie")).tag(ChartStyle.pie)
                Text(L("chart.style.donut")).tag(ChartStyle.donut)
                Text(L("chart.style.bar")).tag(ChartStyle.bar)
            }
            Picker(L("chart.maxSlices"), selection: $appState.chartSettings.maximumSlices) {
                ForEach(Array(ChartSettings.slicesRange), id: \.self) { count in
                    Text(Format.count(count)).tag(count)
                }
            }
            Divider()
            Toggle(L("chart.groupFiles"), isOn: $appState.chartSettings.groupLooseFiles)
            Toggle(L("chart.showFreeSpace"), isOn: $appState.chartSettings.showFreeSpace)
                .disabled(appState.volumeFreeSpace == nil)
            Toggle(L("chart.showPercentages"), isOn: $appState.chartSettings.showPercentages)
        } label: {
            Label(L("chart.settings"), systemImage: "slider.horizontal.3")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L("chart.settings"))
    }

    // MARK: - Chart

    @ViewBuilder
    private var chart: some View {
        switch appState.chartSettings.style {
        case .pie, .donut:
            Chart {
                ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    SectorMark(
                        angle: .value(L("common.size"), Double(slice.size)),
                        innerRadius: .ratio(appState.chartSettings.style == .donut ? 0.55 : 0),
                        angularInset: 1
                    )
                    .cornerRadius(3)
                    .foregroundStyle(color(for: slice, at: index))
                }
            }
            .aspectRatio(1, contentMode: .fit)
        case .bar:
            Chart {
                ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    BarMark(
                        x: .value(L("common.size"), Double(slice.size)),
                        y: .value(L("common.name"), label(for: slice))
                    )
                    .cornerRadius(3)
                    .foregroundStyle(color(for: slice, at: index))
                }
            }
            .chartYScale(domain: slices.map(label(for:)))
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let bytes = value.as(Double.self) {
                            Text(Format.bytes(Int64(bytes)))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Legend

    private var legend: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
                    legendRow(slice, at: index)
                    Divider()
                }
            }
        }
    }

    private func legendRow(_ slice: ChartSlice, at index: Int) -> some View {
        let isFolder = slice.kind == .directory && slice.path != nil
        return Button {
            if let path = slice.path, isFolder { appState.drillIntoChart(path: path) }
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: slice, at: index))
                    .frame(width: 12, height: 12)
                Text(label(for: slice))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if appState.chartSettings.showPercentages {
                    Text(Format.percent(slice.fraction))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Text(Format.bytes(slice.size))
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .opacity(isFolder ? 1 : 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(!isFolder)
    }

    // MARK: - Appearance

    /// Fixed palette rather than the chart default: the legend draws its own
    /// swatches, and both have to agree on which wedge is which.
    private static let palette: [Color] = [
        Color(red: 0.16, green: 0.44, blue: 0.55),
        Color(red: 0.27, green: 0.71, blue: 0.62),
        Color(red: 0.96, green: 0.76, blue: 0.42),
        Color(red: 0.90, green: 0.45, blue: 0.42),
        Color(red: 0.45, green: 0.42, blue: 0.68),
        Color(red: 0.55, green: 0.71, blue: 0.35),
        Color(red: 0.85, green: 0.60, blue: 0.72),
        Color(red: 0.35, green: 0.55, blue: 0.78),
        Color(red: 0.78, green: 0.52, blue: 0.28),
        Color(red: 0.40, green: 0.66, blue: 0.71),
    ]

    private func color(for slice: ChartSlice, at index: Int) -> Color {
        switch slice.kind {
        case .freeSpace: return Color.purple.opacity(0.65)
        case .others: return Color.gray.opacity(0.65)
        default: return Self.palette[index % Self.palette.count]
        }
    }

    private func label(for slice: ChartSlice) -> String {
        switch slice.kind {
        case .looseFiles: return L("chart.looseFiles", Format.count(slice.itemCount))
        case .others: return L("chart.others")
        case .freeSpace: return L("chart.freeSpace")
        case .directory, .file: return slice.name
        }
    }
}
