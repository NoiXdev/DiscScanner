import SwiftUI
import DiscScannerCore

struct ContentView: View {
    @Bindable var appState: AppState

    var body: some View {
        Group {
            if let root = appState.root {
                mainContent(root)
            } else {
                ContentUnavailableView(L("empty.prompt"), systemImage: "internaldrive")
            }
        }
        .frame(minWidth: 700, minHeight: 450)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .top, spacing: 0) {
            if appState.progress.accessDeniedCount > 0 {
                accessDeniedBanner
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
    }

    @ViewBuilder
    private func mainContent(_ root: FileNode) -> some View {
        switch appState.viewMode {
        case .list:
            TreeListView(appState: appState, root: root)
        case .treemap:
            // Replaced with the real treemap in Task 11.
            Text(L("view.treemap"))
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

    private var statusBar: some View {
        HStack {
            if appState.isScanning {
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
