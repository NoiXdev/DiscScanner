import SwiftUI
import UniformTypeIdentifiers
import DiscScannerCore

@MainActor
private enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for node: FileNode) -> NSImage {
        let key: String
        if node.isDirectory {
            key = "//dir"
        } else {
            key = (node.path as NSString).pathExtension.lowercased()
        }

        if let cachedIcon = cache[key] {
            return cachedIcon
        }

        let icon = node.isDirectory
            ? NSWorkspace.shared.icon(for: UTType.folder)
            : NSWorkspace.shared.icon(forFile: node.path)
        cache[key] = icon
        return icon
    }
}

/// One row of the details table.
///
/// The table sorts every level by the same comparators, and this is what
/// makes that affordable: a level is sorted when the table asks for its
/// children, which happens for the rows on screen — not for the whole tree,
/// which on a volume scan has millions of nodes.
struct SortedFileNode: Identifiable {
    let node: FileNode
    let order: [KeyPathComparator<SortedFileNode>]

    var id: String { node.path }
    var name: String { node.name }
    var size: Int64 { node.allocatedSize }
    /// Missing dates sort as oldest rather than dropping out of the column.
    var sortDate: Date { node.modificationDate ?? .distantPast }

    var typeName: String {
        if node.isDirectory { return L("common.folder") }
        let fileExtension = node.fileExtension
        return fileExtension.isEmpty ? L("ext.none") : fileExtension.uppercased()
    }

    var children: [SortedFileNode]? {
        guard node.isDirectory, !node.children.isEmpty else { return nil }
        return Self.rows(of: node, order: order)
    }

    static func rows(
        of node: FileNode,
        order: [KeyPathComparator<SortedFileNode>]
    ) -> [SortedFileNode] {
        node.children
            .map { SortedFileNode(node: $0, order: order) }
            .sorted(using: order)
    }
}

/// The Details tab: the folder you are browsing as a sortable table, with
/// disclosure triangles for what is below it and a double-click to step
/// into a folder — the Finder's list view, over scan data.
struct TreeListView: View {
    @Bindable var appState: AppState
    let root: FileNode

    @State private var sortOrder = [
        KeyPathComparator(\SortedFileNode.size, order: SortOrder.reverse),
    ]

    private var folder: FileNode { appState.detailsNode ?? root }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                BreadcrumbBar(trail: appState.breadcrumb(to: appState.detailsPath)) { node in
                    appState.browseDetails(to: node)
                }
                Spacer(minLength: 12)
                Text(Format.bytes(folder.allocatedSize))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            table
        }
    }

    private var table: some View {
        Table(
            SortedFileNode.rows(of: folder, order: sortOrder),
            children: \.children,
            selection: $appState.selection,
            sortOrder: $sortOrder
        ) {
            TableColumn(L("common.name"), value: \.name) { item in
                nameCell(item.node)
            }
            .width(min: 180, ideal: 340)

            TableColumn(L("common.size"), value: \.size) { item in
                sizeCell(item.node)
            }
            .width(min: 130, ideal: 160)

            TableColumn(L("common.type"), value: \.typeName) { item in
                Text(item.typeName)
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 100)

            TableColumn(L("common.modified"), value: \.sortDate) { item in
                Text(Format.date(item.node.modificationDate))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 160)
        }
        .contextMenu(forSelectionType: String.self) { paths in
            Button(L("menu.open")) { open(paths) }
                .disabled(paths.count != 1)
            Button(L("menu.showInFinder")) { revealInFinder(paths) }
            Button(L("menu.delete"), role: .destructive) { appState.requestDelete(paths: paths) }
                .disabled(appState.isScanning)
        } primaryAction: { paths in
            open(paths)
        }
    }

    private func nameCell(_ node: FileNode) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: IconCache.icon(for: node))
                .resizable()
                .frame(width: 16, height: 16)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            if node.isAccessDenied {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .help(L("row.accessDenied"))
            }
        }
    }

    /// Size plus a bar for the share of the folder being browsed — the
    /// number says how big, the bar says how much of what you are looking at.
    private func sizeCell(_ node: FileNode) -> some View {
        HStack(spacing: 6) {
            SizeBar(fraction: min(1, Double(node.allocatedSize) / Double(max(folder.allocatedSize, 1))))
            Text(Format.bytes(node.allocatedSize))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    /// Double-click and the Open command: a folder is stepped into, a file
    /// is shown where it lives. Opening the file itself is the Finder's job,
    /// not a disk scanner's.
    private func open(_ paths: Set<String>) {
        guard paths.count == 1, let path = paths.first, let node = root.find(path: path) else {
            return
        }
        if node.isDirectory {
            appState.browseDetails(to: node)
        } else {
            revealInFinder(paths)
        }
    }

    private func revealInFinder(_ paths: Set<String>) {
        NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
    }
}

private struct SizeBar: View {
    let fraction: Double

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(.quaternary)
            RoundedRectangle(cornerRadius: 2)
                .fill(.tint.opacity(0.6))
                .frame(width: max(2, 50 * fraction))
        }
        .frame(width: 50, height: 6)
    }
}
