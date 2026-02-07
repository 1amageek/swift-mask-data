import Testing
import Foundation
@testable import LayoutIR

// MARK: - IREdge Edge Cases

@Suite("IREdge Edge Cases")
struct IREdgeEdgeCaseTests {

    @Test func zeroLengthEdge() {
        let e = IREdge(p1: IRPoint(x: 50, y: 50), p2: IRPoint(x: 50, y: 50))
        #expect(e.length == 0.0)
        #expect(e.reversed == e)
    }

    @Test func negativeCoordinates() {
        let e = IREdge(p1: IRPoint(x: -100, y: -200), p2: IRPoint(x: 300, y: 400))
        let dx = 400.0, dy = 600.0
        let expected = (dx * dx + dy * dy).squareRoot()
        #expect(abs(e.length - expected) < 1e-9)
    }

    @Test func int32Extremes() {
        let e = IREdge(p1: IRPoint(x: .min, y: .min), p2: IRPoint(x: .max, y: .max))
        #expect(e.length > 0)
        #expect(e.length.isFinite)
    }

    @Test func reversedIdempotence() {
        let e = IREdge(p1: IRPoint(x: 10, y: 20), p2: IRPoint(x: 30, y: 40))
        #expect(e.reversed.reversed == e)
    }

    @Test func hashConsistency() {
        let a = IREdge(p1: IRPoint(x: 1, y: 2), p2: IRPoint(x: 3, y: 4))
        let b = IREdge(p1: IRPoint(x: 1, y: 2), p2: IRPoint(x: 3, y: 4))
        #expect(a.hashValue == b.hashValue)
    }

    @Test func codableRoundTrip() throws {
        let edge = IREdge(p1: IRPoint(x: -500, y: 1000), p2: IRPoint(x: 2000, y: -3000))
        let data = try JSONEncoder().encode(edge)
        let decoded = try JSONDecoder().decode(IREdge.self, from: data)
        #expect(decoded == edge)
    }
}

// MARK: - IREdgePair Edge Cases

@Suite("IREdgePair Edge Cases")
struct IREdgePairEdgeCaseTests {

    @Test func identicalEdges() {
        let e = IREdge(p1: IRPoint(x: 0, y: 0), p2: IRPoint(x: 100, y: 0))
        let pair = IREdgePair(edge1: e, edge2: e)
        #expect(pair.distance == 0.0)
    }

    @Test func perpendicularEdges() {
        let e1 = IREdge(p1: IRPoint(x: 0, y: 0), p2: IRPoint(x: 100, y: 0))
        let e2 = IREdge(p1: IRPoint(x: 50, y: 0), p2: IRPoint(x: 50, y: 100))
        let pair = IREdgePair(edge1: e1, edge2: e2)
        // Mid1 = (50, 0), Mid2 = (50, 50), distance = 50
        #expect(pair.distance == 50.0)
    }

    @Test func codableRoundTrip() throws {
        let e1 = IREdge(p1: IRPoint(x: 0, y: 0), p2: IRPoint(x: 100, y: 0))
        let e2 = IREdge(p1: IRPoint(x: 0, y: 200), p2: IRPoint(x: 100, y: 200))
        let pair = IREdgePair(edge1: e1, edge2: e2)
        let data = try JSONEncoder().encode(pair)
        let decoded = try JSONDecoder().decode(IREdgePair.self, from: data)
        #expect(decoded == pair)
    }
}
