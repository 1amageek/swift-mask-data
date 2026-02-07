import Testing
@testable import LayoutIR

// MARK: - IREdge Tests

@Suite("IREdge")
struct IREdgeTests {

    @Test func construction() {
        let edge = IREdge(
            p1: IRPoint(x: 0, y: 0),
            p2: IRPoint(x: 100, y: 0)
        )
        #expect(edge.p1 == IRPoint(x: 0, y: 0))
        #expect(edge.p2 == IRPoint(x: 100, y: 0))
    }

    @Test func length() {
        // Horizontal edge
        let h = IREdge(p1: IRPoint(x: 0, y: 0), p2: IRPoint(x: 300, y: 0))
        #expect(h.length == 300.0)

        // Vertical edge
        let v = IREdge(p1: IRPoint(x: 0, y: 0), p2: IRPoint(x: 0, y: 400))
        #expect(v.length == 400.0)

        // Diagonal edge (3-4-5 triangle)
        let d = IREdge(p1: IRPoint(x: 0, y: 0), p2: IRPoint(x: 300, y: 400))
        #expect(d.length == 500.0)
    }

    @Test func reversed() {
        let edge = IREdge(p1: IRPoint(x: 10, y: 20), p2: IRPoint(x: 30, y: 40))
        let rev = edge.reversed
        #expect(rev.p1 == IRPoint(x: 30, y: 40))
        #expect(rev.p2 == IRPoint(x: 10, y: 20))
    }

    @Test func equality() {
        let a = IREdge(p1: IRPoint(x: 0, y: 0), p2: IRPoint(x: 100, y: 200))
        let b = IREdge(p1: IRPoint(x: 0, y: 0), p2: IRPoint(x: 100, y: 200))
        let c = IREdge(p1: IRPoint(x: 100, y: 200), p2: IRPoint(x: 0, y: 0))
        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - IREdgePair Tests

@Suite("IREdgePair")
struct IREdgePairTests {

    @Test func construction() {
        let e1 = IREdge(p1: IRPoint(x: 0, y: 0), p2: IRPoint(x: 100, y: 0))
        let e2 = IREdge(p1: IRPoint(x: 0, y: 50), p2: IRPoint(x: 100, y: 50))
        let pair = IREdgePair(edge1: e1, edge2: e2)
        #expect(pair.edge1 == e1)
        #expect(pair.edge2 == e2)
    }

    @Test func distance() {
        // Two parallel horizontal edges separated by 200 units
        let e1 = IREdge(p1: IRPoint(x: 0, y: 0), p2: IRPoint(x: 100, y: 0))
        let e2 = IREdge(p1: IRPoint(x: 0, y: 200), p2: IRPoint(x: 100, y: 200))
        let pair = IREdgePair(edge1: e1, edge2: e2)
        #expect(pair.distance == 200.0)

        // Two parallel vertical edges separated by 300 units
        let e3 = IREdge(p1: IRPoint(x: 0, y: 0), p2: IRPoint(x: 0, y: 100))
        let e4 = IREdge(p1: IRPoint(x: 300, y: 0), p2: IRPoint(x: 300, y: 100))
        let pair2 = IREdgePair(edge1: e3, edge2: e4)
        #expect(pair2.distance == 300.0)
    }
}
