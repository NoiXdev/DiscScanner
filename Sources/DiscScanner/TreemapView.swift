import SwiftUI
import DiscScannerCore

struct TreemapView: View {
    @Bindable var appState: AppState
    let root: FileNode

    /// The directory currently zoomed into. Falls back to the scan root when
    /// the stored path no longer resolves (e.g. after deletion or a fresh
    /// snapshot).
    private var zoomRoot: FileNode {
        guard
            let path = appState.treemapZoomPath,
            let node = root.find(path: path),
            node.isDirectory
        else { return root }
        return node
    }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumb
            GeometryReader { proxy in
                let bounds = CGRect(origin: .zero, size: proxy.size)
                let tiles = TreemapLayout.layout(items: items(for: zoomRoot), in: bounds)
                Canvas { context, _ in
                    for tile in tiles {
                        guard let node = zoomRoot.find(path: tile.id) else { continue }
                        draw(node: node, in: tile.rect, context: &context)
                    }
                }
                .gesture(tapGestures(tiles: tiles))
                .contextMenu {
                    Button(L("menu.showInFinder")) { revealSelection() }
                    Button(L("menu.delete"), role: .destructive) {
                        appState.requestDelete(paths: appState.selection)
                    }
                }
            }
        }
    }

    private func items(for node: FileNode) -> [TreemapItem] {
        node.children.map { TreemapItem(id: $0.path, weight: Double($0.allocatedSize)) }
    }

    private func draw(node: FileNode, in rect: CGRect, context: inout GraphicsContext) {
        let inset = rect.insetBy(dx: 1, dy: 1)
        guard inset.width > 0, inset.height > 0 else { return }
        let path = Path(roundedRect: inset, cornerRadius: 2)
        context.fill(path, with: .color(tileColor(for: node)))
        if appState.selection.contains(node.path) {
            context.stroke(path, with: .color(.accentColor), lineWidth: 2)
        }
        if inset.width > 60, inset.height > 16 {
            context.draw(
                Text(node.name).font(.caption2).foregroundStyle(.white),
                in: inset.insetBy(dx: 4, dy: 2)
            )
        }
    }

    private func tileColor(for node: FileNode) -> Color {
        if node.isAccessDenied { return .orange.opacity(0.7) }
        let base: Color = node.isDirectory ? .blue : .teal
        let variation = Double(abs(node.name.hashValue % 30)) / 100.0
        return base.opacity(0.55 + variation)
    }

    private func tapGestures(tiles: [TreemapRect]) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                guard
                    let id = hitTest(tiles, at: value.location),
                    let node = zoomRoot.find(path: id),
                    node.isDirectory
                else { return }
                appState.treemapZoomPath = node.path
            }
            .exclusively(before: SpatialTapGesture(count: 1)
                .onEnded { value in
                    if let id = hitTest(tiles, at: value.location) {
                        appState.selection = [id]
                    }
                }
            )
    }

    private func hitTest(_ tiles: [TreemapRect], at point: CGPoint) -> String? {
        tiles.first { $0.rect.contains(point) }?.id
    }

    private func revealSelection() {
        NSWorkspace.shared.activateFileViewerSelecting(
            appState.selection.map { URL(fileURLWithPath: $0) }
        )
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            let crumbs = breadcrumbNodes()
            ForEach(crumbs, id: \.path) { node in
                Button(node.name) {
                    appState.treemapZoomPath = node.path == root.path ? nil : node.path
                }
                .buttonStyle(.link)
                if node.path != crumbs.last?.path {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(6)
        .background(.bar)
    }

    private func breadcrumbNodes() -> [FileNode] {
        var nodes: [FileNode] = [root]
        let zoom = zoomRoot
        guard zoom.path != root.path else { return nodes }
        let relative = zoom.path.dropFirst(root.path.count)
            .split(separator: "/")
            .map(String.init)
        var currentPath = root.path
        var current = root
        for component in relative {
            currentPath += "/" + component
            guard let next = current.find(path: currentPath) else { break }
            nodes.append(next)
            current = next
        }
        return nodes
    }
}
