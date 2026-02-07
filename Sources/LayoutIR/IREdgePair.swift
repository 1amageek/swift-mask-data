import Foundation

public struct IREdgePair: Hashable, Sendable, Codable {
    public var edge1: IREdge
    public var edge2: IREdge

    public init(edge1: IREdge, edge2: IREdge) {
        self.edge1 = edge1
        self.edge2 = edge2
    }

    /// Minimum distance between the midpoints of the two edges.
    public var distance: Double {
        let mid1x = (Double(edge1.p1.x) + Double(edge1.p2.x)) / 2.0
        let mid1y = (Double(edge1.p1.y) + Double(edge1.p2.y)) / 2.0
        let mid2x = (Double(edge2.p1.x) + Double(edge2.p2.x)) / 2.0
        let mid2y = (Double(edge2.p1.y) + Double(edge2.p2.y)) / 2.0
        let dx = mid2x - mid1x
        let dy = mid2y - mid1y
        return (dx * dx + dy * dy).squareRoot()
    }
}
