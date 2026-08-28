import SwiftUI
import DiscScannerCore

@MainActor
private enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for node: FileNode) -> NSImage {
        let cacheKey = node.outlineChildren != nil ? "//dir" : (node.path as NSString).pathExtension.lowercased().isEmpty ? "" : (node.path as NSString).pathExtension.lowercased()

        if let cachedIcon = cache[cacheKey] {
            return cachedIcon
        }

        let icon = NSWorkspace.shared.icon(forFile: node.path)
        cache[cacheKey] = icon
        return icon
    }
}

struct TreeListView: View {
    @Bindable var appState: AppState
    let root: FileNode

    var body: some View {
        List(selection: $appState.selection) {
            ForEach(root.children) { child in
                TreeNodeView(node: child, parentSize: max(root.allocatedSize, 1))
            }
        }
        .contextMenu(forSelectionType: String.self) { paths in
            Button(L("menu.showInFinder")) { revealInFinder(paths) }
        }
    }

    private func revealInFinder(_ paths: Set<String>) {
        NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
    }
}

private struct TreeNodeView: View {
    let node: FileNode
    let parentSize: Int64

    var body: some View {
        if let children = node.outlineChildren {
            DisclosureGroup {
                ForEach(children) { child in
                    TreeNodeView(node: child, parentSize: max(node.allocatedSize, 1))
                }
            } label: {
                FileRowView(node: node, parentSize: parentSize)
            }
            .tag(node.id)
        } else {
            FileRowView(node: node, parentSize: parentSize)
                .tag(node.id)
        }
    }
}

private struct FileRowView: View {
    let node: FileNode
    let parentSize: Int64

    private var fraction: Double {
        min(1, Double(node.allocatedSize) / Double(parentSize))
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: IconCache.icon(for: node))
                .resizable()
                .frame(width: 16, height: 16)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            if node.isAccessDenied {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SizeBar(fraction: fraction)
            Text(Format.bytes(node.allocatedSize))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
        }
    }
}

private struct SizeBar: View {
    let fraction: Double

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(.quaternary)
            RoundedRectangle(cornerRadius: 2)
                .fill(.tint.opacity(0.6))
                .frame(width: max(2, 60 * fraction))
        }
        .frame(width: 60, height: 6)
    }
}
