import SwiftUI
import DiscScannerCore

/// The path from the scan root to wherever a tab is drilled in, as a row of
/// links plus a way up. The chart and the details table navigate the same
/// tree in two different ways and share this.
struct BreadcrumbBar: View {
    let trail: [FileNode]
    /// Called with the node to move to; the host decides what that means.
    let onSelect: (FileNode) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if trail.count > 1 { onSelect(trail[trail.count - 2]) }
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(trail.count < 2)
            .help(L("nav.up"))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(trail.enumerated()), id: \.element.id) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Button(node.name.isEmpty ? node.path : node.name) { onSelect(node) }
                            .buttonStyle(.link)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}
