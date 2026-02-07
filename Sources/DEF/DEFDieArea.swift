import LayoutIR

/// Represents a DIEAREA in DEF, supporting both rectangular and polygon forms.
public struct DEFDieArea: Hashable, Sendable, Codable {
    public var points: [IRPoint]

    public init(points: [IRPoint]) {
        self.points = points
    }

    /// Convenience init for rectangular die area (2-point form).
    public init(x1: Int32, y1: Int32, x2: Int32, y2: Int32) {
        self.points = [IRPoint(x: x1, y: y1), IRPoint(x: x2, y: y2)]
    }

    /// Returns the bounding box if available.
    public var boundingBox: (x1: Int32, y1: Int32, x2: Int32, y2: Int32)? {
        guard !points.isEmpty else { return nil }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        return (xs.min()!, ys.min()!, xs.max()!, ys.max()!)
    }

    /// Whether this is a simple rectangular die area (exactly 2 points).
    public var isRectangular: Bool {
        points.count == 2
    }
}
