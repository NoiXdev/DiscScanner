import Foundation
import CoreGraphics

public struct TreemapItem: Sendable, Equatable {
    public let id: String
    public let weight: Double

    public init(id: String, weight: Double) {
        self.id = id
        self.weight = weight
    }
}

public struct TreemapRect: Sendable, Equatable {
    public let id: String
    public let rect: CGRect

    public init(id: String, rect: CGRect) {
        self.id = id
        self.rect = rect
    }
}

/// Squarified treemap (Bruls, Huizing, van Wijk). Greedily fills rows along
/// the shorter side of the remaining rectangle while the worst aspect ratio
/// keeps improving.
public enum TreemapLayout {
    public static func layout(items: [TreemapItem], in bounds: CGRect) -> [TreemapRect] {
        let positive = items.filter { $0.weight > 0 }.sorted { $0.weight > $1.weight }
        let totalWeight = positive.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0, bounds.width > 0, bounds.height > 0 else { return [] }

        let scale = Double(bounds.width * bounds.height) / totalWeight
        let areas = positive.map { (id: $0.id, area: $0.weight * scale) }

        var result: [TreemapRect] = []
        var remaining = bounds
        var row: [(id: String, area: Double)] = []

        func worstAspect(_ candidate: [(id: String, area: Double)], side: Double) -> Double {
            guard side > 0, !candidate.isEmpty else { return .infinity }
            let total = candidate.reduce(0.0) { $0 + $1.area }
            guard total > 0 else { return .infinity }
            let thickness = total / side
            var worst = 0.0
            for item in candidate {
                let length = item.area / thickness
                worst = max(worst, max(length / thickness, thickness / length))
            }
            return worst
        }

        func flushRow() {
            let total = row.reduce(0.0) { $0 + $1.area }
            defer { row = [] }
            guard total > 0 else { return }
            if remaining.width >= remaining.height {
                // shorter side is the height: lay a vertical strip on the left
                let stripWidth = CGFloat(total / Double(remaining.height))
                var y = remaining.minY
                for item in row {
                    let height = CGFloat(item.area / Double(stripWidth))
                    result.append(TreemapRect(
                        id: item.id,
                        rect: CGRect(x: remaining.minX, y: y, width: stripWidth, height: height)
                    ))
                    y += height
                }
                remaining = CGRect(
                    x: remaining.minX + stripWidth,
                    y: remaining.minY,
                    width: remaining.width - stripWidth,
                    height: remaining.height
                )
            } else {
                // shorter side is the width: lay a horizontal strip on top
                let stripHeight = CGFloat(total / Double(remaining.width))
                var x = remaining.minX
                for item in row {
                    let width = CGFloat(item.area / Double(stripHeight))
                    result.append(TreemapRect(
                        id: item.id,
                        rect: CGRect(x: x, y: remaining.minY, width: width, height: stripHeight)
                    ))
                    x += width
                }
                remaining = CGRect(
                    x: remaining.minX,
                    y: remaining.minY + stripHeight,
                    width: remaining.width,
                    height: remaining.height - stripHeight
                )
            }
        }

        for item in areas {
            let side = Double(min(remaining.width, remaining.height))
            if row.isEmpty || worstAspect(row + [item], side: side) <= worstAspect(row, side: side) {
                row.append(item)
            } else {
                flushRow()
                row.append(item)
            }
        }
        flushRow()
        return result
    }
}
