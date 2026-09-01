import AppKit
import SwiftUI
import DiscScannerCore

/// The History tab: saved scans on the left, and what changed between two of
/// them on the right. A scan on its own says how full the disk is; two of
/// them say where it went.
struct HistoryTabView: View {
    @Bindable var appState: AppState

    var body: some View {
        VSplitView {
            savedScansSection
                .frame(minHeight: 160, idealHeight: 240)
            comparisonSection
                .frame(minHeight: 200)
        }
        .onAppear { appState.refreshSavedScans() }
    }

    // MARK: - Saved scans

    private var savedScansSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Shown on its own, without the tab bar, this view needs its
                // own way back to the empty state.
                if appState.root == nil {
                    Button {
                        appState.isShowingSavedScans = false
                    } label: {
                        Label(L("common.back"), systemImage: "chevron.left")
                    }
                }
                Button {
                    appState.saveCurrentScan()
                } label: {
                    Label(L("history.save"), systemImage: "square.and.arrow.down")
                }
                .disabled(appState.root == nil || appState.isScanning || appState.isSavingScan)
                if appState.isSavingScan {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button {
                    appState.refreshSavedScans()
                } label: {
                    Label(L("common.refresh"), systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .help(L("common.refresh"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()

            if appState.savedScans.isEmpty {
                ContentUnavailableView(L("history.empty"), systemImage: "clock.arrow.circlepath")
            } else {
                Table(appState.savedScans) {
                    TableColumn(L("common.name")) { entry in
                        Text(entry.summary.displayName)
                    }
                    TableColumn(L("common.date")) { entry in
                        Text(Format.date(entry.summary.createdAt)).monospacedDigit()
                    }
                    .width(min: 130, ideal: 160)
                    TableColumn(L("common.size")) { entry in
                        Text(Format.bytes(entry.summary.totalAllocatedSize)).monospacedDigit()
                    }
                    .width(min: 90, ideal: 110)
                    TableColumn(L("common.files")) { entry in
                        Text(Format.count(entry.summary.fileCount)).monospacedDigit()
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("") { entry in
                        HStack(spacing: 4) {
                            Button(L("common.open")) { appState.openSaved(entry) }
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                            } label: {
                                Image(systemName: "folder")
                            }
                            .help(L("menu.showInFinder"))
                            Button(role: .destructive) {
                                appState.deleteSaved(entry)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .help(L("common.delete"))
                        }
                        .buttonStyle(.borderless)
                    }
                    .width(min: 120, ideal: 140)
                }
            }
        }
    }

    // MARK: - Comparison

    private var comparisonSection: some View {
        VStack(spacing: 0) {
            comparisonControls
            Divider()
            if let comparison = appState.comparison {
                comparisonResult(comparison)
            } else {
                ContentUnavailableView(L("history.compareHint"), systemImage: "arrow.left.arrow.right")
            }
        }
    }

    private var comparisonControls: some View {
        HStack(spacing: 8) {
            Picker(L("history.baseline"), selection: $appState.comparisonBaseline) {
                Text(L("common.none")).tag(UUID?.none)
                ForEach(appState.savedScans) { entry in
                    Text(title(for: entry)).tag(UUID?.some(entry.id))
                }
            }
            .frame(maxWidth: 280)

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            Picker(L("history.target"), selection: $appState.comparisonTarget) {
                Text(L("history.currentScan")).tag(AppState.ComparisonTarget.currentScan)
                ForEach(appState.savedScans) { entry in
                    Text(title(for: entry)).tag(AppState.ComparisonTarget.saved(entry.id))
                }
            }
            .frame(maxWidth: 280)

            Button(L("history.compare")) { appState.runComparison() }
                .disabled(!appState.canCompare || appState.isComparing)
            if appState.isComparing {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func comparisonResult(_ comparison: ComparisonReport) -> some View {
        VStack(spacing: 0) {
            summaryBar(comparison)
            Divider()
            if comparison.entries.isEmpty {
                ContentUnavailableView(L("history.noChanges"), systemImage: "equal.circle")
            } else {
                Table(comparison.entries) {
                    TableColumn(L("common.name")) { entry in
                        Label {
                            Text(entry.name)
                        } icon: {
                            Image(systemName: icon(for: entry.kind))
                                .foregroundStyle(tint(for: entry.kind))
                        }
                    }
                    TableColumn(L("history.delta")) { entry in
                        Text(Format.signedBytes(entry.delta))
                            .monospacedDigit()
                            .foregroundStyle(tint(for: entry.kind))
                    }
                    .width(min: 90, ideal: 110)
                    TableColumn(L("history.before")) { entry in
                        Text(Format.bytes(entry.oldSize)).monospacedDigit()
                    }
                    .width(min: 80, ideal: 100)
                    TableColumn(L("history.after")) { entry in
                        Text(Format.bytes(entry.newSize)).monospacedDigit()
                    }
                    .width(min: 80, ideal: 100)
                    TableColumn(L("common.path")) { entry in
                        Text(entry.path)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(.secondary)
                            .help(entry.path)
                    }
                }
            }
        }
    }

    private func summaryBar(_ comparison: ComparisonReport) -> some View {
        HStack(spacing: 12) {
            if let labels = appState.comparisonLabels {
                Text("\(labels.baseline) → \(labels.target)")
                    .lineLimit(1)
            }
            Text(Format.signedBytes(comparison.delta))
                .monospacedDigit()
                .fontWeight(.semibold)
                .foregroundStyle(comparison.delta >= 0 ? Color.orange : Color.green)
            Spacer()
            Text(L("history.counts",
                   Format.count(comparison.addedCount),
                   Format.count(comparison.removedCount),
                   Format.count(comparison.grownCount),
                   Format.count(comparison.shrunkCount)))
            .foregroundStyle(.secondary)
            if comparison.isTruncated {
                Text(L("history.truncated", Format.count(comparison.entries.count)))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func title(for entry: ScanStore.Entry) -> String {
        "\(entry.summary.displayName) · \(Format.date(entry.summary.createdAt))"
    }

    private func icon(for kind: ChangeEntry.Kind) -> String {
        switch kind {
        case .added: return "plus.circle"
        case .removed: return "minus.circle"
        case .grown: return "arrow.up.circle"
        case .shrunk: return "arrow.down.circle"
        }
    }

    private func tint(for kind: ChangeEntry.Kind) -> Color {
        switch kind {
        case .added, .grown: return .orange
        case .removed, .shrunk: return .green
        }
    }
}
