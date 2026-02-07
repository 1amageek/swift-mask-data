import LayoutIR
import Foundation

/// Corner modes for polygon sizing operations.
public enum CornerMode: Sendable, Hashable {
    /// Square (right angle) corners — Manhattan offset.
    case square
    /// 45-degree chamfered corners.
    case octagonal
    /// Rounded corners with specified number of segments per quadrant.
    case round(segments: Int)
}

/// Sizing operations using Minkowski sum/difference for proper corner handling.
enum MinkowskiSizing {

    /// Size a polygon by the given amount with the specified corner mode.
    static func size(_ polygon: IRBoundary, by amount: Int32, cornerMode: CornerMode, layer: Int16) -> [IRBoundary] {
        var pts = polygon.points
        PolygonUtils.ensureCCW(&pts)
        PolygonUtils.ensureClosed(&pts)

        if pts.count > 1 && pts.last == pts.first {
            pts.removeLast()
        }
        guard pts.count >= 3 else { return [] }

        let offsetPoints: [IRPoint]
        switch cornerMode {
        case .square:
            offsetPoints = offsetSquare(pts, by: amount)
        case .octagonal:
            offsetPoints = offsetOctagonal(pts, by: amount)
        case .round(let segments):
            offsetPoints = offsetRound(pts, by: amount, segmentsPerQuadrant: max(segments, 1))
        }

        guard offsetPoints.count >= 3 else { return [] }

        // Validate area (negative amount should shrink)
        var result = offsetPoints
        PolygonUtils.ensureClosed(&result)
        let resultArea = PolygonUtils.area(result)
        if resultArea == 0 { return [] }

        return [IRBoundary(layer: layer, datatype: 0, points: result, properties: [])]
    }

    // MARK: - Square Corner Offset

    private static func offsetSquare(_ pts: [IRPoint], by amount: Int32) -> [IRPoint] {
        let n = pts.count
        var result: [IRPoint] = []

        for i in 0..<n {
            let prev = pts[(i + n - 1) % n]
            let curr = pts[i]
            let next = pts[(i + 1) % n]

            // Edge normals (outward for CCW polygon)
            let (n1x, n1y) = edgeNormal(from: prev, to: curr)
            let (n2x, n2y) = edgeNormal(from: curr, to: next)

            // Offset vertex: intersection of the two offset edges
            let p1x = Double(curr.x) + n1x * Double(amount)
            let p1y = Double(curr.y) + n1y * Double(amount)
            let p2x = Double(curr.x) + n2x * Double(amount)
            let p2y = Double(curr.y) + n2y * Double(amount)

            // Average for simple square corner
            let ox = (p1x + p2x) / 2.0
            let oy = (p1y + p2y) / 2.0

            // Use miter intersection for proper square corners
            if let miter = miterPoint(
                curr: curr,
                n1: (n1x, n1y), n2: (n2x, n2y),
                amount: Double(amount)
            ) {
                result.append(miter)
            } else {
                result.append(IRPoint(x: Int32(ox.rounded()), y: Int32(oy.rounded())))
            }
        }

        return result
    }

    // MARK: - Octagonal Corner Offset

    private static func offsetOctagonal(_ pts: [IRPoint], by amount: Int32) -> [IRPoint] {
        let n = pts.count
        var result: [IRPoint] = []
        let chamferFraction = 1.0 - 1.0 / 2.0.squareRoot()  // ~0.293

        for i in 0..<n {
            let prev = pts[(i + n - 1) % n]
            let curr = pts[i]
            let next = pts[(i + 1) % n]

            let (n1x, n1y) = edgeNormal(from: prev, to: curr)
            let (n2x, n2y) = edgeNormal(from: curr, to: next)

            // Edge directions
            let d1 = direction(from: prev, to: curr)
            let d2 = direction(from: curr, to: next)

            // Use miter point as reference for proper corner offset
            if let miter = miterPoint(curr: curr, n1: (n1x, n1y), n2: (n2x, n2y), amount: Double(amount)) {
                let mx = Double(miter.x)
                let my = Double(miter.y)
                // Chamfer: offset from miter along edge tangent directions
                let chamferDist = Double(abs(amount)) * chamferFraction
                let c1x = mx - d1.0 * chamferDist
                let c1y = my - d1.1 * chamferDist
                let c2x = mx + d2.0 * chamferDist
                let c2y = my + d2.1 * chamferDist
                result.append(IRPoint(x: Int32(c1x.rounded()), y: Int32(c1y.rounded())))
                result.append(IRPoint(x: Int32(c2x.rounded()), y: Int32(c2y.rounded())))
            } else {
                // Fallback: use average normal for degenerate cases
                let ox = Double(curr.x) + (n1x + n2x) / 2.0 * Double(amount)
                let oy = Double(curr.y) + (n1y + n2y) / 2.0 * Double(amount)
                result.append(IRPoint(x: Int32(ox.rounded()), y: Int32(oy.rounded())))
            }
        }

        return result
    }

    // MARK: - Round Corner Offset

    private static func offsetRound(_ pts: [IRPoint], by amount: Int32, segmentsPerQuadrant: Int) -> [IRPoint] {
        let n = pts.count
        var result: [IRPoint] = []

        for i in 0..<n {
            let prev = pts[(i + n - 1) % n]
            let curr = pts[i]
            let next = pts[(i + 1) % n]

            let (n1x, n1y) = edgeNormal(from: prev, to: curr)
            let (n2x, n2y) = edgeNormal(from: curr, to: next)

            // Angle between normals
            let angle1 = atan2(n1y, n1x)
            let angle2 = atan2(n2y, n2x)

            // Ensure we sweep in the correct direction
            var sweep = angle2 - angle1
            if amount > 0 {
                if sweep < 0 { sweep += 2.0 * .pi }
            } else {
                if sweep > 0 { sweep -= 2.0 * .pi }
            }

            let absSweep = abs(sweep)
            let numSegs = max(1, Int(Double(segmentsPerQuadrant) * absSweep / (.pi / 2.0)))

            let cx = Double(curr.x)
            let cy = Double(curr.y)
            let r = Double(abs(amount))

            for s in 0...numSegs {
                let t = Double(s) / Double(numSegs)
                let angle = angle1 + t * sweep
                let px = cx + r * cos(angle)
                let py = cy + r * sin(angle)
                result.append(IRPoint(x: Int32(px.rounded()), y: Int32(py.rounded())))
            }
        }

        return result
    }

    // MARK: - Geometry Helpers

    private static func edgeNormal(from a: IRPoint, to b: IRPoint) -> (Double, Double) {
        let dx = Double(b.x) - Double(a.x)
        let dy = Double(b.y) - Double(a.y)
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0 else { return (0, 0) }
        // Normal pointing outward for CCW polygon: perpendicular right = (dy, -dx) / len
        return (dy / len, -dx / len)
    }

    private static func direction(from a: IRPoint, to b: IRPoint) -> (Double, Double) {
        let dx = Double(b.x) - Double(a.x)
        let dy = Double(b.y) - Double(a.y)
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0 else { return (0, 0) }
        return (dx / len, dy / len)
    }

    private static func miterPoint(
        curr: IRPoint,
        n1: (Double, Double), n2: (Double, Double),
        amount: Double
    ) -> IRPoint? {
        // Bisector direction
        let bx = n1.0 + n2.0
        let by = n1.1 + n2.1
        let blen = (bx * bx + by * by).squareRoot()
        guard blen > 1e-9 else { return nil }

        let dot = n1.0 * bx / blen + n1.1 * by / blen
        guard abs(dot) > 1e-9 else { return nil }

        let d = amount / dot
        let ox = Double(curr.x) + d * bx / blen
        let oy = Double(curr.y) + d * by / blen
        return IRPoint(x: Int32(ox.rounded()), y: Int32(oy.rounded()))
    }
}
