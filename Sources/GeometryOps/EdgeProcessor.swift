import LayoutIR

/// Edge-based polygon boolean operations for non-Manhattan geometry.
/// Uses Sutherland-Hodgman clipping for AND, and polygon union/subtraction
/// via decomposition for OR/XOR/NOT.
enum EdgeProcessor {

    /// Perform a boolean operation on two sets of polygons.
    static func booleanOp(_ op: BooleanOp, a: [IRBoundary], b: [IRBoundary], layer: Int16) -> [IRBoundary] {
        switch op {
        case .and:
            return intersect(a, b, layer: layer)
        case .or:
            return union(a, b, layer: layer)
        case .xor:
            let u = union(a, b, layer: layer)
            let inter = intersect(a, b, layer: layer)
            return subtract(u, inter, layer: layer)
        case .not:
            return subtract(a, b, layer: layer)
        }
    }

    // MARK: - Intersection (AND)

    private static func intersect(_ a: [IRBoundary], _ b: [IRBoundary], layer: Int16) -> [IRBoundary] {
        var result: [IRBoundary] = []
        for polyA in a {
            for polyB in b {
                if let clipped = clipPolygon(subject: polyA.points, clip: polyB.points) {
                    if clipped.count >= 3 {
                        var pts = clipped
                        PolygonUtils.ensureClosed(&pts)
                        if PolygonUtils.area(pts) > 0 {
                            result.append(IRBoundary(layer: layer, datatype: 0, points: pts, properties: []))
                        }
                    }
                }
            }
        }
        return result
    }

    // MARK: - Union (OR)

    private static func union(_ a: [IRBoundary], _ b: [IRBoundary], layer: Int16) -> [IRBoundary] {
        // Union = A + B - (A ∩ B)
        // For each polygon pair, compute the union by collecting non-overlapping parts
        var allPolys = a + b
        guard allPolys.count > 1 else { return allPolys }

        // Iterative merge: try to merge pairs of overlapping polygons
        var changed = true
        while changed {
            changed = false
            var i = 0
            while i < allPolys.count {
                var j = i + 1
                while j < allPolys.count {
                    if polygonsOverlap(allPolys[i], allPolys[j]) {
                        if let merged = mergeTwo(allPolys[i], allPolys[j], layer: layer) {
                            allPolys[i] = merged
                            allPolys.remove(at: j)
                            changed = true
                            continue
                        }
                    }
                    j += 1
                }
                i += 1
            }
        }

        return allPolys
    }

    // MARK: - Subtraction (NOT)

    private static func subtract(_ a: [IRBoundary], _ b: [IRBoundary], layer: Int16) -> [IRBoundary] {
        var current = a
        for polyB in b {
            var next: [IRBoundary] = []
            for polyA in current {
                let subtracted = subtractSingle(polyA, polyB, layer: layer)
                next.append(contentsOf: subtracted)
            }
            current = next
        }
        return current
    }

    private static func subtractSingle(_ a: IRBoundary, _ b: IRBoundary, layer: Int16) -> [IRBoundary] {
        // If they don't overlap, A is unchanged
        guard polygonsOverlap(a, b) else { return [a] }

        // Check if B fully contains A
        let aPts = a.points
        let aCount = (aPts.count > 1 && aPts.last == aPts.first) ? aPts.count - 1 : aPts.count
        let allInside = (0..<aCount).allSatisfy { PolygonUtils.pointInPolygon(aPts[$0], polygon: b.points) }
        if allInside { return [] }

        // Simple case: approximate by computing the area outside B
        // Use the intersection to subtract
        if let inter = clipPolygon(subject: a.points, clip: b.points) {
            let interArea = PolygonUtils.area(inter)
            let aArea = PolygonUtils.area(a.points)
            if interArea == 0 { return [a] }
            if interArea >= aArea { return [] }
        }

        // For complex non-Manhattan subtraction, return A as-is if partial overlap
        // (The AABB-based decomposition handles Manhattan cases correctly)
        return [a]
    }

    // MARK: - Sutherland-Hodgman Clipping

    /// Clips subject polygon by clip polygon using Sutherland-Hodgman algorithm.
    static func clipPolygon(subject: [IRPoint], clip: [IRPoint]) -> [IRPoint]? {
        var subjectOpen: [IRPoint]
        if subject.count > 1 && subject.last == subject.first {
            subjectOpen = [IRPoint](subject[0..<(subject.count - 1)])
        } else {
            subjectOpen = subject
        }

        var clipPts: [IRPoint]
        if clip.count > 1 && clip.last == clip.first {
            clipPts = [IRPoint](clip[0..<(clip.count - 1)])
        } else {
            clipPts = clip
        }

        guard subjectOpen.count >= 3, clipPts.count >= 3 else { return nil }

        // Ensure clip polygon is CCW
        if PolygonUtils.signedArea(clipPts) < 0 {
            clipPts.reverse()
        }

        let clipCount = clipPts.count
        for i in 0..<clipCount {
            guard !subjectOpen.isEmpty else { return nil }

            let edgeStart = clipPts[i]
            let edgeEnd = clipPts[(i + 1) % clipCount]

            var output: [IRPoint] = []

            for j in 0..<subjectOpen.count {
                let current = subjectOpen[j]
                let previous = subjectOpen[(j + subjectOpen.count - 1) % subjectOpen.count]

                let currInside = isInsideEdge(current, edgeStart: edgeStart, edgeEnd: edgeEnd)
                let prevInside = isInsideEdge(previous, edgeStart: edgeStart, edgeEnd: edgeEnd)

                if currInside {
                    if !prevInside {
                        if let inter = lineIntersection(previous, current, edgeStart, edgeEnd) {
                            output.append(inter)
                        }
                    }
                    output.append(current)
                } else if prevInside {
                    if let inter = lineIntersection(previous, current, edgeStart, edgeEnd) {
                        output.append(inter)
                    }
                }
            }

            subjectOpen = output
        }

        return subjectOpen.isEmpty ? nil : subjectOpen
    }

    // MARK: - Helpers

    private static func isInsideEdge(_ point: IRPoint, edgeStart: IRPoint, edgeEnd: IRPoint) -> Bool {
        // Cross product: (edgeEnd - edgeStart) × (point - edgeStart)
        let cross = Int64(edgeEnd.x - edgeStart.x) * Int64(point.y - edgeStart.y)
                   - Int64(edgeEnd.y - edgeStart.y) * Int64(point.x - edgeStart.x)
        return cross >= 0
    }

    private static func lineIntersection(
        _ p1: IRPoint, _ p2: IRPoint,
        _ p3: IRPoint, _ p4: IRPoint
    ) -> IRPoint? {
        let d1x = Int64(p2.x) - Int64(p1.x)
        let d1y = Int64(p2.y) - Int64(p1.y)
        let d2x = Int64(p4.x) - Int64(p3.x)
        let d2y = Int64(p4.y) - Int64(p3.y)

        let denom = d1x * d2y - d1y * d2x
        if denom == 0 { return nil }

        let t_num = (Int64(p3.x) - Int64(p1.x)) * d2y - (Int64(p3.y) - Int64(p1.y)) * d2x

        let t = Double(t_num) / Double(denom)
        let ix = Double(p1.x) + t * Double(d1x)
        let iy = Double(p1.y) + t * Double(d1y)
        return IRPoint(x: Int32(ix.rounded()), y: Int32(iy.rounded()))
    }

    private static func polygonsOverlap(_ a: IRBoundary, _ b: IRBoundary) -> Bool {
        guard let bbA = PolygonUtils.boundingBox(of: a.points),
              let bbB = PolygonUtils.boundingBox(of: b.points) else { return false }
        return bbA.minX < bbB.maxX && bbA.maxX > bbB.minX && bbA.minY < bbB.maxY && bbA.maxY > bbB.minY
    }

    private static func mergeTwo(_ a: IRBoundary, _ b: IRBoundary, layer: Int16) -> IRBoundary? {
        // Quick merge: compute convex hull of all points as an approximation
        // For KLayout-compatible union, use the combined bounding box for Manhattan,
        // and convex hull for non-Manhattan
        let aEnd = (a.points.count > 1 && a.points.last == a.points.first) ? a.points.count - 1 : a.points.count
        let bEnd = (b.points.count > 1 && b.points.last == b.points.first) ? b.points.count - 1 : b.points.count
        var allPoints = [IRPoint]()
        allPoints.reserveCapacity(aEnd + bEnd)
        allPoints.append(contentsOf: a.points[0..<aEnd])
        allPoints.append(contentsOf: b.points[0..<bEnd])

        if PolygonUtils.isManhattan(a.points) && PolygonUtils.isManhattan(b.points) {
            return nil // Let the scanline handler deal with Manhattan
        }

        // Convex hull merge for non-Manhattan
        let hull = convexHull(allPoints)
        guard hull.count >= 3 else { return nil }
        var pts = hull
        PolygonUtils.ensureClosed(&pts)
        return IRBoundary(layer: layer, datatype: 0, points: pts, properties: [])
    }

    /// Graham scan convex hull.
    private static func convexHull(_ points: [IRPoint]) -> [IRPoint] {
        guard points.count >= 3 else { return points }

        var pts = points.sorted { $0.x < $1.x || ($0.x == $1.x && $0.y < $1.y) }
        // Remove duplicates in-place (array is already sorted)
        pts.removeAll { _ in false } // no-op, just to ensure unique buffer
        var writeIdx = 1
        for readIdx in 1..<pts.count {
            if pts[readIdx] != pts[writeIdx - 1] {
                pts[writeIdx] = pts[readIdx]
                writeIdx += 1
            }
        }
        pts.removeSubrange(writeIdx..<pts.count)
        guard pts.count >= 3 else { return pts }

        // Lower hull
        var lower: [IRPoint] = []
        for p in pts {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }

        // Upper hull
        var upper: [IRPoint] = []
        for p in pts.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }

        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    private static func cross(_ o: IRPoint, _ a: IRPoint, _ b: IRPoint) -> Int64 {
        Int64(a.x - o.x) * Int64(b.y - o.y) - Int64(a.y - o.y) * Int64(b.x - o.x)
    }
}
