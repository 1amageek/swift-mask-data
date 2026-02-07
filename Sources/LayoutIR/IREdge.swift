import Foundation

public struct IREdge: Hashable, Sendable, Codable {
    public var p1: IRPoint
    public var p2: IRPoint

    public init(p1: IRPoint, p2: IRPoint) {
        self.p1 = p1
        self.p2 = p2
    }

    public var reversed: IREdge {
        IREdge(p1: p2, p2: p1)
    }

    public var length: Double {
        let dx = Double(p2.x) - Double(p1.x)
        let dy = Double(p2.y) - Double(p1.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}
