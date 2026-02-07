import LayoutIR

/// Geometry utility functions for polygon operations.
public enum PolygonUtils {

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
    public static func ensureCCW(_ points: inout [IRPoint]) {
        if signedArea(points) < 0 {
            let hasClosed = points.count > 1 && points.first == points.last
            if hasClosed {
                // Reverse in-place excluding the closing point, then fix it
                let lastIdx = points.count - 1
                var lo = 0, hi = lastIdx - 1
                while lo < hi {
                    points.swapAt(lo, hi)
                    lo += 1; hi -= 1
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

    /// Tests whether two line segments (p1-p2) and (p3-p4) intersect.
    /// Returns the intersection point if they do.
    public static func segmentIntersection(
        _ p1: IRPoint, _ p2: IRPoint,
        _ p3: IRPoint, _ p4: IRPoint
    ) -> IRPoint? {
        // Using Int64 cross products for exact arithmetic
        let d1x = Int64(p2.x) - Int64(p1.x)
        let d1y = Int64(p2.y) - Int64(p1.y)
        let d2x = Int64(p4.x) - Int64(p3.x)
        let d2y = Int64(p4.y) - Int64(p3.y)

        let denom = d1x * d2y - d1y * d2x
        if denom == 0 { return nil } // Parallel or coincident

        let t_num = (Int64(p3.x) - Int64(p1.x)) * d2y - (Int64(p3.y) - Int64(p1.y)) * d2x
        let u_num = (Int64(p3.x) - Int64(p1.x)) * d1y - (Int64(p3.y) - Int64(p1.y)) * d1x

        // Check if 0 <= t <= 1 and 0 <= u <= 1
        if denom > 0 {
            if t_num < 0 || t_num > denom { return nil }
            if u_num < 0 || u_num > denom { return nil }
        } else {
            if t_num > 0 || t_num < denom { return nil }
            if u_num > 0 || u_num < denom { return nil }
        }

        let ix = Double(p1.x) + Double(t_num) / Double(denom) * Double(d1x)
        let iy = Double(p1.y) + Double(t_num) / Double(denom) * Double(d1y)
        return IRPoint(x: Int32(ix.rounded()), y: Int32(iy.rounded()))
    }

    /// Point-in-polygon test using ray casting.
    public static func pointInPolygon(_ point: IRPoint, polygon: [IRPoint]) -> Bool {
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

    /// Minimum distance between two line segments.
    public static func segmentDistance(
        _ p1: IRPoint, _ p2: IRPoint,
        _ p3: IRPoint, _ p4: IRPoint
    ) -> Double {
        // Check if segments intersect
        if segmentIntersection(p1, p2, p3, p4) != nil { return 0 }

        // Minimum of point-to-segment distances
        return min(
            pointToSegmentDistance(p1, p3, p4),
            pointToSegmentDistance(p2, p3, p4),
            pointToSegmentDistance(p3, p1, p2),
            pointToSegmentDistance(p4, p1, p2)
        )
    }

    /// Distance from a point to a line segment.
    public static func pointToSegmentDistance(_ point: IRPoint, _ seg1: IRPoint, _ seg2: IRPoint) -> Double {
        let px = Double(point.x), py = Double(point.y)
        let ax = Double(seg1.x), ay = Double(seg1.y)
        let bx = Double(seg2.x), by = Double(seg2.y)

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
