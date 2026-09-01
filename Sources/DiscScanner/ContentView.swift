import AppKit
import SwiftUI
import DiscScannerCore

struct ContentView: View {
    @Bindable var appState: AppState
    @State private var showFullDiskAccessAlert = false

    var body: some View {
        content
        // Without the maxima a view that is content to be small — the
        // history, say — floats in the middle of the window.
        .frame(
            minWidth: 520, maxWidth: .infinity,
            minHeight: 420, maxHeight: .infinity
        )
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if case .updateAvailable(let release) = appState.updateOutcome,
                   !appState.updateBannerDismissed {
                    updateBanner(release)
                }
                if appState.progress.accessDeniedCount > 0, !appState.accessBannerDismissed {
                    accessDeniedBanner
                }
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
        .alert(
            L("history.error"),
            isPresented: Binding(
                get: { appState.storeError != nil },
                set: { if !$0 { appState.storeError = nil } }
            )
        ) {
            Button(L("common.ok"), role: .cancel) { appState.storeError = nil }
        } message: {
            Text(appState.storeError ?? "")
        }
        .alert(
            L("update.title"),
            isPresented: Binding(
                get: { appState.updateMessage != nil },
                set: { if !$0 { appState.updateMessage = nil } }
            )
        ) {
            Button(L("common.ok"), role: .cancel) { appState.updateMessage = nil }
        } message: {
            Text(appState.updateMessage ?? "")
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
            appState.checkForUpdates(force: false)
        }
    }

    /// Below this width the tab bar stops fitting eight titles and turns
    /// into a menu.
    private static let compactWidth: CGFloat = 840

    /// With no scan there is nothing to put in seven of the eight tabs, so
    /// the bar stays away entirely and the window is just the invitation to
    /// scan — plus the one door that does work without a scan: the history,
    /// because opening a saved scan is how you get one without waiting.
    @ViewBuilder
    private var content: some View {
        if appState.root != nil {
            scanContent
        } else if appState.isShowingSavedScans {
            HistoryTabView(appState: appState)
        } else {
            emptyState
        }
    }

    private var scanContent: some View {
        GeometryReader { proxy in
            Group {
                if proxy.size.width < Self.compactWidth {
                    VStack(spacing: 0) {
                        tabPicker
                        Divider()
                        tabContent(appState.tab)
                    }
                } else {
                    TabView(selection: $appState.tab) {
                        ForEach(AppState.Tab.allCases) { tab in
                            tabContent(tab)
                                .tabItem { Label(title(of: tab), systemImage: icon(of: tab)) }
                                .tag(tab)
                        }
                    }
                }
            }
            // A GeometryReader sizes its content to the child's ideal size,
            // not to the space it measured — without this the tabs would sit
            // in the corner of the window.
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var tabPicker: some View {
        HStack {
            Picker(L("tab.section"), selection: $appState.tab) {
                ForEach(AppState.Tab.allCases) { tab in
                    Label(title(of: tab), systemImage: icon(of: tab)).tag(tab)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func tabContent(_ tab: AppState.Tab) -> some View {
        switch tab {
        case .chart:
            ChartTabView(appState: appState)
        case .details:
            treeTab
        case .treemap:
            treemapTab
        case .fileExtensions:
            ExtensionsTabView(
                statistics: appState.statistics,
                isComputing: appState.isComputingStatistics
            )
        case .users:
            UsersTabView(
                statistics: appState.statistics,
                isComputing: appState.isComputingStatistics
            )
        case .age:
            AgeTabView(
                statistics: appState.statistics,
                isComputing: appState.isComputingStatistics
            )
        case .topFiles:
            TopFilesTabView(
                statistics: appState.statistics,
                isComputing: appState.isComputingStatistics
            )
        case .history:
            HistoryTabView(appState: appState)
        }
    }

    // Spelled out rather than derived from the raw value: a renamed case
    // would otherwise silently lose its title.
    private func title(of tab: AppState.Tab) -> String {
        switch tab {
        case .chart: return L("tab.chart")
        case .details: return L("tab.details")
        case .treemap: return L("tab.treemap")
        case .fileExtensions: return L("tab.extensions")
        case .users: return L("tab.users")
        case .age: return L("tab.age")
        case .topFiles: return L("tab.topFiles")
        case .history: return L("tab.history")
        }
    }

    private func icon(of tab: AppState.Tab) -> String {
        switch tab {
        case .chart: return "chart.pie"
        case .details: return "list.bullet.indent"
        case .treemap: return "square.grid.3x3.fill"
        case .fileExtensions: return "doc.text"
        case .users: return "person.2"
        case .age: return "calendar"
        case .topFiles: return "arrow.up.doc"
        case .history: return "clock.arrow.circlepath"
        }
    }

    @ViewBuilder
    private var treeTab: some View {
        if let root = appState.root {
            TreeListView(appState: appState, root: root)
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private var treemapTab: some View {
        if let root = appState.root {
            TreemapView(appState: appState, root: root)
        } else {
            emptyState
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(L("app.open"), systemImage: "folder") { openFolder() }
        }
        ToolbarItem {
            Button {
                appState.saveCurrentScan()
            } label: {
                Label(L("history.save"), systemImage: "square.and.arrow.down")
            }
            .disabled(appState.root == nil || appState.isScanning || appState.isSavingScan)
            .help(L("history.save"))
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
                Button {
                    appState.isShowingSavedScans = true
                } label: {
                    Label(L("empty.savedScans"), systemImage: "clock.arrow.circlepath")
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

    private func updateBanner(_ release: ReleaseInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
            Text(L("update.available", release.displayName))
            Button(L("update.open")) {
                NSWorkspace.shared.open(release.htmlURL)
            }
            .buttonStyle(.link)
            Spacer()
            Button {
                appState.dismissUpdateBanner()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L("update.dismiss"))
        }
        .font(.callout)
        .padding(8)
        .background(.tint.opacity(0.12))
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
