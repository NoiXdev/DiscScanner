import Testing
import Foundation
@testable import DiscScannerCore

struct TreemapLayoutTests {
    private let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)

    private func makeItems(_ weights: [Double]) -> [TreemapItem] {
        weights.enumerated().map { TreemapItem(id: "item\($0.offset)", weight: $0.element) }
    }

    @Test func tilesFullAreaWithoutOverlap() {
        let rects = TreemapLayout.layout(items: makeItems([6, 6, 4, 3, 2, 2, 1]), in: bounds)
        #expect(rects.count == 7)

        let totalArea = rects.reduce(0.0) { $0 + Double($1.rect.width * $1.rect.height) }
        #expect(abs(totalArea - 240_000) < 1.0)

        let tolerantBounds = bounds.insetBy(dx: -0.5, dy: -0.5)
        for tile in rects {
            #expect(tolerantBounds.contains(tile.rect))
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].rect.intersection(rects[j].rect)
                let overlapArea = Double(max(0, overlap.width) * max(0, overlap.height))
                #expect(overlapArea < 1.0)
            }
        }
    }

    @Test func areasAreProportionalToWeights() {
        let rects = TreemapLayout.layout(items: makeItems([6, 6, 4, 3, 2, 2, 1]), in: bounds)
        let first = rects.first { $0.id == "item0" }!
        let area = Double(first.rect.width * first.rect.height)
        #expect(abs(area - 240_000.0 * 6.0 / 24.0) < 1.0)
    }

    @Test func dropsNonPositiveWeights() {
        let rects = TreemapLayout.layout(items: makeItems([5, 0, -1]), in: bounds)
        #expect(rects.count == 1)
        #expect(rects[0].id == "item0")
    }

    @Test func emptyInputProducesEmptyLayout() {
        #expect(TreemapLayout.layout(items: [], in: bounds).isEmpty)
        #expect(TreemapLayout.layout(items: makeItems([1]), in: .zero).isEmpty)
    }
}
