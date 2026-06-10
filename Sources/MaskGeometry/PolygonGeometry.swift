import LayoutIR

/// Polygon geometry queries and normalization routines.
public enum PolygonGeometry {

    /// Returns the edges of a polygon (consecutive point pairs).
    public static func edges(of points: [IRPoint]) -> [IREdge] {
        guard points.count >= 2 else { return [] }
        var result: [IREdge] = []
        for i in 0..<(points.count - 1) {
            result.append(IREdge(p1: points[i], p2: points[i + 1]))
        }
        return result
    }

    /// Signed area of a polygon (positive = CCW, negative = CW).
    public static func signedArea(_ points: [IRPoint]) -> Int64 {
        guard points.count >= 3 else { return 0 }
        var area: Int64 = 0
        let n = points.last == points.first ? points.count - 1 : points.count
        for i in 0..<n {
            let j = (i + 1) % n
            area += Int64(points[i].x) * Int64(points[j].y)
            area -= Int64(points[j].x) * Int64(points[i].y)
        }
        return area / 2
    }

    /// Unsigned area of a polygon.
    public static func area(_ points: [IRPoint]) -> Int64 {
        abs(signedArea(points))
    }

    /// Ensures points are in counter-clockwise order.
    public static func ensureCounterClockwise(_ points: inout [IRPoint]) {
        if signedArea(points) < 0 {
            let hasClosed = points.count > 1 && points.first == points.last
            if hasClosed {
                // Reverse in-place excluding the closing point, then fix it.
                let lastIdx = points.count - 1
                var lo = 0, hi = lastIdx - 1
                while lo < hi {
                    points.swapAt(lo, hi)
                    lo += 1
                    hi -= 1
                }
                points[lastIdx] = points[0]
            } else {
                points.reverse()
            }
        }
    }

    /// Ensures polygon is closed (first == last).
    public static func ensureClosed(_ points: inout [IRPoint]) {
        guard points.count >= 3 else { return }
        if points.first != points.last {
            points.append(points[0])
        }
    }

    /// Returns the intersection point for two edges when they intersect.
    public static func intersection(of first: IREdge, and second: IREdge) -> IRPoint? {
        // Using Int64 cross products for exact arithmetic
        let d1x = Int64(first.p2.x) - Int64(first.p1.x)
        let d1y = Int64(first.p2.y) - Int64(first.p1.y)
        let d2x = Int64(second.p2.x) - Int64(second.p1.x)
        let d2y = Int64(second.p2.y) - Int64(second.p1.y)

        let denom = d1x * d2y - d1y * d2x
        if denom == 0 { return nil } // Parallel or coincident

        let tNumerator = (Int64(second.p1.x) - Int64(first.p1.x)) * d2y
            - (Int64(second.p1.y) - Int64(first.p1.y)) * d2x
        let uNumerator = (Int64(second.p1.x) - Int64(first.p1.x)) * d1y
            - (Int64(second.p1.y) - Int64(first.p1.y)) * d1x

        // Check if 0 <= t <= 1 and 0 <= u <= 1
        if denom > 0 {
            if tNumerator < 0 || tNumerator > denom { return nil }
            if uNumerator < 0 || uNumerator > denom { return nil }
        } else {
            if tNumerator > 0 || tNumerator < denom { return nil }
            if uNumerator > 0 || uNumerator < denom { return nil }
        }

        let ix = Double(first.p1.x) + Double(tNumerator) / Double(denom) * Double(d1x)
        let iy = Double(first.p1.y) + Double(tNumerator) / Double(denom) * Double(d1y)
        return IRPoint(x: Int32(ix.rounded()), y: Int32(iy.rounded()))
    }

    /// Point-in-polygon test using ray casting.
    public static func contains(_ point: IRPoint, in polygon: [IRPoint]) -> Bool {
        let n = polygon.last == polygon.first ? polygon.count - 1 : polygon.count
        guard n >= 3 else { return false }

        var inside = false
        let px = Int64(point.x)
        let py = Int64(point.y)

        var j = n - 1
        for i in 0..<n {
            let xi = Int64(polygon[i].x), yi = Int64(polygon[i].y)
            let xj = Int64(polygon[j].x), yj = Int64(polygon[j].y)

            if ((yi > py) != (yj > py)) &&
               (px < (xj - xi) * (py - yi) / (yj - yi) + xi) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Computes the axis-aligned bounding box of a polygon in a single pass (zero allocation).
    public static func boundingBox(of points: [IRPoint]) -> (minX: Int32, minY: Int32, maxX: Int32, maxY: Int32)? {
        guard let first = points.first else { return nil }
        var minX = first.x, minY = first.y
        var maxX = first.x, maxY = first.y
        for i in 1..<points.count {
            let p = points[i]
            if p.x < minX { minX = p.x }
            if p.y < minY { minY = p.y }
            if p.x > maxX { maxX = p.x }
            if p.y > maxY { maxY = p.y }
        }
        return (minX, minY, maxX, maxY)
    }

    /// Checks if a polygon is Manhattan (all edges axis-aligned).
    public static func isManhattan(_ points: [IRPoint]) -> Bool {
        guard points.count >= 3 else { return true }
        let n = points.last == points.first ? points.count - 1 : points.count
        for i in 0..<n {
            let j = (i + 1) % n
            if points[i].x != points[j].x && points[i].y != points[j].y {
                return false
            }
        }
        return true
    }

    /// Minimum distance between two edges.
    public static func distance(between first: IREdge, and second: IREdge) -> Double {
        // Check if segments intersect
        if intersection(of: first, and: second) != nil { return 0 }

        // Minimum of point-to-segment distances
        return min(
            distance(from: first.p1, to: second),
            distance(from: first.p2, to: second),
            distance(from: second.p1, to: first),
            distance(from: second.p2, to: first)
        )
    }

    /// Distance from a point to an edge.
    public static func distance(from point: IRPoint, to edge: IREdge) -> Double {
        let px = Double(point.x), py = Double(point.y)
        let ax = Double(edge.p1.x), ay = Double(edge.p1.y)
        let bx = Double(edge.p2.x), by = Double(edge.p2.y)

        let dx = bx - ax
        let dy = by - ay
        let lenSq = dx * dx + dy * dy

        if lenSq == 0 {
            // Degenerate segment
            let d2 = (px - ax) * (px - ax) + (py - ay) * (py - ay)
            return d2.squareRoot()
        }

        // Project point onto line, clamping t to [0, 1]
        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lenSq))
        let projX = ax + t * dx
        let projY = ay + t * dy
        let d2 = (px - projX) * (px - projX) + (py - projY) * (py - projY)
        return d2.squareRoot()
    }
}
