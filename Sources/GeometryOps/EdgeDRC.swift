import LayoutIR
import Foundation

/// Distance metric for DRC checks (KLayout compatible).
public enum DRCMetric: Sendable, Hashable {
    /// True Euclidean distance.
    case euclidean
    /// Chebyshev (L-infinity) distance — max of |dx|, |dy|.
    case square
    /// Edge normal projection distance.
    case projection
}

/// Edge-based DRC checks supporting multiple distance metrics.
enum EdgeDRC {

    /// Check minimum width of each polygon.
    static func widthCheck(_ region: Region, minWidth: Int32, metric: DRCMetric) -> [IREdgePair] {
        var violations: [IREdgePair] = []

        for poly in region.polygons {
            let edges = PolygonUtils.edges(of: poly.points)
            guard edges.count >= 3 else { continue }

            // Check distance between non-adjacent edges
            for i in 0..<edges.count {
                guard i + 2 < edges.count else { continue }
                for j in (i + 2)..<edges.count {
                    // Skip adjacent edges (they share a vertex)
                    if j == edges.count - 1 && i == 0 { continue }

                    let dist = edgeDistance(edges[i], edges[j], metric: metric)
                    if dist > 0 && dist < Double(minWidth) {
                        violations.append(IREdgePair(edge1: edges[i], edge2: edges[j]))
                    }
                }
            }
        }

        return violations
    }

    /// Check minimum spacing between two regions.
    static func spaceCheck(_ a: Region, _ b: Region, minSpace: Int32, metric: DRCMetric) -> [IREdgePair] {
        var violations: [IREdgePair] = []

        for polyA in a.polygons {
            let edgesA = PolygonUtils.edges(of: polyA.points)
            for polyB in b.polygons {
                let edgesB = PolygonUtils.edges(of: polyB.points)

                for ea in edgesA {
                    for eb in edgesB {
                        let dist = edgeDistance(ea, eb, metric: metric)
                        if dist > 0 && dist < Double(minSpace) {
                            violations.append(IREdgePair(edge1: ea, edge2: eb))
                        }
                    }
                }
            }
        }

        return violations
    }

    /// Check minimum enclosure of inner by outer region.
    static func enclosureCheck(outer: Region, inner: Region, minEnclosure: Int32, metric: DRCMetric) -> [IREdgePair] {
        var violations: [IREdgePair] = []

        for innerPoly in inner.polygons {
            let innerEdges = PolygonUtils.edges(of: innerPoly.points)

            for outerPoly in outer.polygons {
                let outerEdges = PolygonUtils.edges(of: outerPoly.points)

                for ie in innerEdges {
                    var minDist = Double.infinity
                    var closestEdge = outerEdges.first!

                    for oe in outerEdges {
                        let dist = edgeDistance(ie, oe, metric: metric)
                        if dist < minDist {
                            minDist = dist
                            closestEdge = oe
                        }
                    }

                    if minDist < Double(minEnclosure) {
                        violations.append(IREdgePair(edge1: ie, edge2: closestEdge))
                    }
                }
            }
        }

        return violations
    }

    /// Check for notch violations (minimum distance between edges of the same polygon
    /// that face each other across a concavity).
    static func notchCheck(_ region: Region, minNotch: Int32, metric: DRCMetric) -> [IREdgePair] {
        var violations: [IREdgePair] = []

        for poly in region.polygons {
            let edges = PolygonUtils.edges(of: poly.points)
            guard edges.count >= 4 else { continue }

            for i in 0..<edges.count {
                guard i + 2 < edges.count else { continue }
                for j in (i + 2)..<edges.count {
                    if j == edges.count - 1 && i == 0 { continue }

                    // Check if edges face each other (normals point towards each other)
                    if edgesFaceEachOther(edges[i], edges[j]) {
                        let dist = edgeDistance(edges[i], edges[j], metric: metric)
                        if dist > 0 && dist < Double(minNotch) {
                            violations.append(IREdgePair(edge1: edges[i], edge2: edges[j]))
                        }
                    }
                }
            }
        }

        return violations
    }

    /// Check minimum separation between two regions.
    static func separationCheck(_ a: Region, _ b: Region, minSeparation: Int32, metric: DRCMetric) -> [IREdgePair] {
        // Same as space check for general metric
        spaceCheck(a, b, minSpace: minSeparation, metric: metric)
    }

    /// Check that all polygon vertices lie on a grid.
    static func gridCheck(_ region: Region, gridX: Int32, gridY: Int32) -> [IREdgePair] {
        var violations: [IREdgePair] = []

        for poly in region.polygons {
            let pts = poly.points
            let count = (pts.count > 1 && pts.last == pts.first) ? pts.count - 1 : pts.count
            for idx in 0..<count {
                let pt = pts[idx]
                let offGridX = gridX > 0 && (pt.x % gridX != 0)
                let offGridY = gridY > 0 && (pt.y % gridY != 0)
                if offGridX || offGridY {
                    // Report as a zero-length edge pair at the offending point
                    let edge = IREdge(p1: pt, p2: pt)
                    let snapped = IRPoint(
                        x: gridX > 0 ? ((pt.x + gridX / 2) / gridX) * gridX : pt.x,
                        y: gridY > 0 ? ((pt.y + gridY / 2) / gridY) * gridY : pt.y
                    )
                    let snapEdge = IREdge(p1: snapped, p2: snapped)
                    violations.append(IREdgePair(edge1: edge, edge2: snapEdge))
                }
            }
        }

        return violations
    }

    /// Check that all polygon edge angles are within allowed set (in degrees).
    static func angleCheck(_ region: Region, allowedAngles: Set<Int>) -> [IREdgePair] {
        var violations: [IREdgePair] = []

        for poly in region.polygons {
            let edges = PolygonUtils.edges(of: poly.points)
            for edge in edges {
                let dx = Double(edge.p2.x - edge.p1.x)
                let dy = Double(edge.p2.y - edge.p1.y)
                guard dx != 0 || dy != 0 else { continue }

                var angleDeg = atan2(dy, dx) * 180.0 / .pi
                if angleDeg < 0 { angleDeg += 360.0 }

                // Normalize to 0-180 range (edge direction doesn't matter)
                let normalizedAngle = Int(angleDeg.rounded()) % 180

                if !allowedAngles.contains(normalizedAngle) {
                    violations.append(IREdgePair(edge1: edge, edge2: edge))
                }
            }
        }

        return violations
    }

    // MARK: - Distance Calculations

    private static func edgeDistance(_ e1: IREdge, _ e2: IREdge, metric: DRCMetric) -> Double {
        switch metric {
        case .euclidean:
            return PolygonUtils.segmentDistance(e1.p1, e1.p2, e2.p1, e2.p2)
        case .square:
            return chebyshevSegmentDistance(e1, e2)
        case .projection:
            return projectionDistance(e1, e2)
        }
    }

    /// Chebyshev (L∞) distance between two segments.
    private static func chebyshevSegmentDistance(_ e1: IREdge, _ e2: IREdge) -> Double {
        // L∞ distance = max(|dx|, |dy|) for closest point pair
        let points1 = [e1.p1, e1.p2]
        let points2 = [e2.p1, e2.p2]

        var minDist = Double.infinity
        for p1 in points1 {
            for p2 in points2 {
                let dx = abs(Double(p1.x) - Double(p2.x))
                let dy = abs(Double(p1.y) - Double(p2.y))
                let dist = max(dx, dy)
                minDist = min(minDist, dist)
            }
        }

        // Also check midpoints of each segment to closest point on the other
        let mid1 = IRPoint(x: (e1.p1.x + e1.p2.x) / 2, y: (e1.p1.y + e1.p2.y) / 2)
        let mid2 = IRPoint(x: (e2.p1.x + e2.p2.x) / 2, y: (e2.p1.y + e2.p2.y) / 2)
        for p in [mid1] {
            for q in points2 + [mid2] {
                let dx = abs(Double(p.x) - Double(q.x))
                let dy = abs(Double(p.y) - Double(q.y))
                minDist = min(minDist, max(dx, dy))
            }
        }
        for p in [mid2] {
            for q in points1 {
                let dx = abs(Double(p.x) - Double(q.x))
                let dy = abs(Double(p.y) - Double(q.y))
                minDist = min(minDist, max(dx, dy))
            }
        }

        return minDist
    }

    /// Edge normal projection distance.
    private static func projectionDistance(_ e1: IREdge, _ e2: IREdge) -> Double {
        // Project endpoints of each edge onto the normal of the other
        let n1 = edgeNormal(e1)
        let n2 = edgeNormal(e2)

        var minDist = Double.infinity

        // Project e2 endpoints onto e1's normal
        for p in [e2.p1, e2.p2] {
            let dx = Double(p.x) - Double(e1.p1.x)
            let dy = Double(p.y) - Double(e1.p1.y)
            let proj = abs(dx * n1.0 + dy * n1.1)
            minDist = min(minDist, proj)
        }

        // Project e1 endpoints onto e2's normal
        for p in [e1.p1, e1.p2] {
            let dx = Double(p.x) - Double(e2.p1.x)
            let dy = Double(p.y) - Double(e2.p1.y)
            let proj = abs(dx * n2.0 + dy * n2.1)
            minDist = min(minDist, proj)
        }

        return minDist
    }

    private static func edgeNormal(_ edge: IREdge) -> (Double, Double) {
        let dx = Double(edge.p2.x) - Double(edge.p1.x)
        let dy = Double(edge.p2.y) - Double(edge.p1.y)
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0 else { return (0, 1) }
        return (-dy / len, dx / len)
    }

    private static func edgesFaceEachOther(_ e1: IREdge, _ e2: IREdge) -> Bool {
        let n1 = edgeNormal(e1)
        let n2 = edgeNormal(e2)

        // Edges face each other if their normals point in roughly opposite directions
        let dot = n1.0 * n2.0 + n1.1 * n2.1
        return dot < -0.5

    }
}
