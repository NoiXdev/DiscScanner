import SwiftUI
import DiscScannerCore

struct ContentView: View {
    @Bindable var appState: AppState
    @State private var showFullDiskAccessAlert = false

    var body: some View {
        Group {
            if let root = appState.root {
                mainContent(root)
            } else {
                emptyState
            }
        }
        .frame(minWidth: 700, minHeight: 450)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .top, spacing: 0) {
            if appState.progress.accessDeniedCount > 0, !appState.accessBannerDismissed {
                accessDeniedBanner
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        .confirmationDialog(
            L(
                "delete.title",
                Format.count(appState.pendingDeletePaths.count),
                Format.bytes(appState.pendingDeleteSize)
            ),
            isPresented: $appState.showDeleteDialog,
            titleVisibility: .visible
        ) {
            Button(L("delete.trash")) { appState.performDelete(method: .trash) }
            Button(L("delete.permanent"), role: .destructive) {
                appState.performDelete(method: .permanent)
            }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(
                ([L("delete.message")] + appState.pendingDeletePaths.prefix(8))
                    .joined(separator: "\n")
            )
        }
        .alert(L("delete.failures.title"), isPresented: $appState.showFailureAlert) {
            Button(L("common.ok"), role: .cancel) {}
        } message: {
            Text(
                appState.deletionFailures
                    .prefix(5)
                    .map { "\($0.path): \($0.message)" }
                    .joined(separator: "\n")
            )
        }
        .alert(L("fda.title"), isPresented: $showFullDiskAccessAlert) {
            Button(L("fda.openSettings")) { FullDiskAccess.openSystemSettings() }
            Button(L("fda.later"), role: .cancel) {}
        } message: {
            Text(L("fda.message"))
        }
        .onAppear {
            if !FullDiskAccess.isGranted {
                showFullDiskAccessAlert = true
            }
        }
    }

    @ViewBuilder
    private func mainContent(_ root: FileNode) -> some View {
        switch appState.viewMode {
        case .list:
            TreeListView(appState: appState, root: root)
        case .treemap:
            TreemapView(appState: appState, root: root)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(L("app.open"), systemImage: "folder") { openFolder() }
        }
        ToolbarItem {
            Picker(L("view.list"), selection: $appState.viewMode) {
                Text(L("view.list")).tag(AppState.ViewMode.list)
                Text(L("view.treemap")).tag(AppState.ViewMode.treemap)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        if appState.isScanning {
            ToolbarItem {
                ProgressView().controlSize(.small)
            }
            ToolbarItem {
                Button(L("app.cancel")) { appState.cancelScan() }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("DiscScanner", systemImage: "internaldrive")
        } description: {
            Text(L("empty.prompt"))
        } actions: {
            HStack(spacing: 12) {
                Button {
                    appState.startScan(url: URL(fileURLWithPath: "/"))
                } label: {
                    Label(L("empty.scanRoot", rootVolumeName), systemImage: "internaldrive")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    openFolder()
                } label: {
                    Label(L("app.open"), systemImage: "folder")
                }
            }
        }
    }

    private var rootVolumeName: String {
        let values = try? URL(fileURLWithPath: "/")
            .resourceValues(forKeys: [.volumeLocalizedNameKey])
        return values?.volumeLocalizedName ?? "Macintosh HD"
    }

    /// Elapsed time, plus percentage and a rough remaining-time estimate for
    /// volume-root scans (folder scans have no predictable total).
    private var scanTimingInfo: String {
        var parts: [String] = []
        guard let start = appState.scanStartDate else { return "" }
        let elapsed = Date().timeIntervalSince(start)
        parts.append(Format.duration(elapsed))
        if let expected = appState.expectedTotalBytes, expected > 0 {
            let fraction = min(Double(appState.progress.totalBytes) / Double(expected), 1)
            parts.append("\(Int(fraction * 100)) %")
            if fraction > 0.05, fraction < 1 {
                let remaining = elapsed * (1 - fraction) / fraction
                parts.append(L("status.remaining", Format.duration(remaining)))
            }
        }
        return parts.joined(separator: " · ")
    }

    private var statusBar: some View {
        HStack {
            if appState.isScanning {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(scanTimingInfo)
                        .monospacedDigit()
                }
                Text(L("status.scanning", appState.progress.currentPath))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if appState.root != nil {
                Text(L("status.done"))
            }
            Spacer()
            Text(L(
                "status.summary",
                Format.count(appState.progress.filesScanned),
                Format.count(appState.progress.directoriesScanned),
                Format.bytes(appState.progress.totalBytes)
            ))
            .monospacedDigit()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var accessDeniedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(L("banner.accessDenied", Format.count(appState.progress.accessDeniedCount)))
            Spacer()
            Button {
                appState.accessBannerDismissed = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .font(.callout)
        .padding(8)
        .background(.yellow.opacity(0.15))
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("app.open")
        if panel.runModal() == .OK, let url = panel.url {
            appState.startScan(url: url)
        }
    }
}
