import LayoutIR

/// Boolean operations on regions using scanline decomposition (Manhattan)
/// or edge processor (non-Manhattan).
enum RegionBoolean {

    static func perform(_ op: BooleanOperation, _ a: Region, _ b: Region) -> Region {
        do {
            return try checkedPerform(op, a, b)
        } catch {
            return performGeneral(op, a, b)
        }
    }

    static func checkedPerform(_ op: BooleanOperation, _ a: Region, _ b: Region) throws -> Region {
        for (index, polygon) in a.polygons.enumerated() {
            guard PolygonGeometry.isManhattan(polygon.points) else {
                throw RegionBooleanError.unsupportedNonManhattanGeometry(
                    operand: "left",
                    polygonIndex: index
                )
            }
        }
        for (index, polygon) in b.polygons.enumerated() {
            guard PolygonGeometry.isManhattan(polygon.points) else {
                throw RegionBooleanError.unsupportedNonManhattanGeometry(
                    operand: "right",
                    polygonIndex: index
                )
            }
        }
        return try performManhattan(op, a, b)
    }

    // MARK: - Manhattan Path (scanline decomposition)

    private static func performManhattan(_ op: BooleanOperation, _ a: Region, _ b: Region) throws -> Region {
        var resultBands: [Band] = []

        try ScanlineSweep.checkedSweepRows(decompose(a), decompose(b)) { yMin, yMax, intervalsA, intervalsB in
            let result: [Interval]
            switch op {
            case .or:
                result = unionIntervals(intervalsA + intervalsB)
            case .and:
                result = intersectIntervals(intervalsA, intervalsB)
            case .xor:
                let u = unionIntervals(intervalsA + intervalsB)
                let inter = intersectIntervals(intervalsA, intervalsB)
                result = subtractIntervals(u, inter)
            case .not:
                result = subtractIntervals(intervalsA, intervalsB)
            }

            for interval in result {
                resultBands.append(Band(xMin: interval.lo, xMax: interval.hi, yMin: yMin, yMax: yMax))
            }
        }

        guard !resultBands.isEmpty else {
            return Region(layer: a.layer)
        }

        let polys = resultBands.map { band -> IRBoundary in
            IRBoundary(layer: a.layer, datatype: 0, points: [
                IRPoint(x: band.xMin, y: band.yMin),
                IRPoint(x: band.xMax, y: band.yMin),
                IRPoint(x: band.xMax, y: band.yMax),
                IRPoint(x: band.xMin, y: band.yMax),
                IRPoint(x: band.xMin, y: band.yMin),
            ], properties: [])
        }

        return Region(layer: a.layer, polygons: mergeRectangles(polys, layer: a.layer))
    }

    // MARK: - General Path (edge processor)

    private static func performGeneral(_ op: BooleanOperation, _ a: Region, _ b: Region) -> Region {
        let result = EdgeProcessor.perform(op, on: a.polygons, b.polygons, layer: a.layer)
        return Region(layer: a.layer, polygons: result)
    }

    // MARK: - Band Decomposition

    struct Band {
        var xMin: Int32, xMax: Int32, yMin: Int32, yMax: Int32
    }

    struct Interval {
        var lo: Int32, hi: Int32
    }

    static func decompose(_ region: Region) -> [Band] {
        var bands: [Band] = []
        for poly in region.polygons {
            bands.append(contentsOf: decompose(poly))
        }
        return bands
    }

    /// Bands of the union coverage of all polygons: per scanline row, abutting
    /// and overlapping x-intervals are coalesced, then vertically adjacent
    /// rows with the identical x-interval are merged. Unlike `decompose`, the
    /// seam between two stacked polygons of the same feature never splits a
    /// row's coverage, so a band edge here is always a true region boundary.
    /// The vertical merge makes the result canonical: the global sweep splits
    /// rows at every y-coordinate in the region, so without it the bands of
    /// one connected component would fragment differently depending on what
    /// unrelated geometry happens to share the region.
    static func unionBands(_ region: Region) -> [Band] {
        do {
            return try checkedUnionBands(region)
        } catch {
            return []
        }
    }

    static func checkedUnionBands(_ region: Region) throws -> [Band] {
        var rows: [Band] = []
        try ScanlineSweep.checkedSweepRows(decompose(region), []) { yMin, yMax, intervals, _ in
            for interval in unionIntervals(intervals) {
                rows.append(Band(xMin: interval.lo, xMax: interval.hi, yMin: yMin, yMax: yMax))
            }
        }
        guard rows.count > 1 else { return rows }
        rows.sort {
            ($0.xMin, $0.xMax, $0.yMin) < ($1.xMin, $1.xMax, $1.yMin)
        }
        var merged: [Band] = [rows[0]]
        for index in 1..<rows.count {
            let current = rows[index]
            let last = merged[merged.count - 1]
            if last.xMin == current.xMin && last.xMax == current.xMax && last.yMax == current.yMin {
                merged[merged.count - 1].yMax = current.yMax
            } else {
                merged.append(current)
            }
        }
        return merged
    }

    private static func decompose(_ polygon: IRBoundary) -> [Band] {
        let points = normalizedPoints(polygon.points)
        guard points.count >= 3 else { return [] }

        let sortedYs = Array(Set(points.map(\.y))).sorted()
        guard sortedYs.count >= 2 else { return [] }

        var bands: [Band] = []

        for index in 0..<(sortedYs.count - 1) {
            let yMin = sortedYs[index]
            let yMax = sortedYs[index + 1]
            guard yMin < yMax else { continue }

            let sampleY = (Double(yMin) + Double(yMax)) / 2.0
            let xs = verticalIntersections(in: points, at: sampleY)

            var pairIndex = 0
            while pairIndex + 1 < xs.count {
                let xMin = xs[pairIndex]
                let xMax = xs[pairIndex + 1]
                if xMin < xMax {
                    bands.append(Band(xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax))
                }
                pairIndex += 2
            }
        }

        return bands
    }

    private static func normalizedPoints(_ points: [IRPoint]) -> [IRPoint] {
        guard points.count > 1, points.first == points.last else {
            return points
        }
        return Array(points.dropLast())
    }

    private static func verticalIntersections(in points: [IRPoint], at sampleY: Double) -> [Int32] {
        var xs: [Int32] = []

        for index in points.indices {
            let nextIndex = index == points.index(before: points.endIndex) ? points.startIndex : points.index(after: index)
            let p1 = points[index]
            let p2 = points[nextIndex]

            guard p1.x == p2.x else { continue }

            let edgeYMin = Double(min(p1.y, p2.y))
            let edgeYMax = Double(max(p1.y, p2.y))
            if edgeYMin <= sampleY && sampleY < edgeYMax {
                xs.append(p1.x)
            }
        }

        return xs.sorted()
    }

    static func unionIntervals(_ intervals: [Interval]) -> [Interval] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.lo < $1.lo }
        var result: [Interval] = [sorted[0]]
        for i in 1..<sorted.count {
            if sorted[i].lo <= result[result.count - 1].hi {
                result[result.count - 1].hi = max(result[result.count - 1].hi, sorted[i].hi)
            } else {
                result.append(sorted[i])
            }
        }
        return result
    }

    static func intersectIntervals(_ a: [Interval], _ b: [Interval]) -> [Interval] {
        var result: [Interval] = []
        var i = 0, j = 0
        let sa = a.sorted { $0.lo < $1.lo }
        let sb = b.sorted { $0.lo < $1.lo }
        while i < sa.count && j < sb.count {
            let lo = max(sa[i].lo, sb[j].lo)
            let hi = min(sa[i].hi, sb[j].hi)
            if lo < hi {
                result.append(Interval(lo: lo, hi: hi))
            }
            if sa[i].hi < sb[j].hi { i += 1 } else { j += 1 }
        }
        return result
    }

    static func subtractIntervals(_ a: [Interval], _ b: [Interval]) -> [Interval] {
        guard !a.isEmpty else { return [] }
        guard !b.isEmpty else { return a }
        var result: [Interval] = []
        let sa = a.sorted { $0.lo < $1.lo }
        let sb = b.sorted { $0.lo < $1.lo }

        for interval in sa {
            var current = interval.lo
            for sub in sb {
                if sub.hi <= current { continue }
                if sub.lo >= interval.hi { break }
                if sub.lo > current {
                    result.append(Interval(lo: current, hi: sub.lo))
                }
                current = max(current, sub.hi)
            }
            if current < interval.hi {
                result.append(Interval(lo: current, hi: interval.hi))
            }
        }
        return result
    }

    // MARK: - Merge

    static func mergeRectangles(_ rects: [IRBoundary], layer: Int16) -> [IRBoundary] {
        guard !rects.isEmpty else { return [] }

        struct Rect: Hashable {
            var minX: Int32, minY: Int32, maxX: Int32, maxY: Int32
        }

        let boxes = rects.compactMap { poly -> Rect? in
            guard let bb = PolygonGeometry.boundingBox(of: poly.points) else { return nil }
            return Rect(minX: bb.minX, minY: bb.minY, maxX: bb.maxX, maxY: bb.maxY)
        }.sorted { $0.minX < $1.minX || ($0.minX == $1.minX && $0.minY < $1.minY) }

        var merged: [Rect] = [boxes[0]]
        for i in 1..<boxes.count {
            let last = merged[merged.count - 1]
            let cur = boxes[i]
            if last.minX == cur.minX && last.maxX == cur.maxX && last.maxY == cur.minY {
                merged[merged.count - 1].maxY = cur.maxY
            } else {
                merged.append(cur)
            }
        }

        return merged.map { r in
            IRBoundary(layer: layer, datatype: 0, points: [
                IRPoint(x: r.minX, y: r.minY),
                IRPoint(x: r.maxX, y: r.minY),
                IRPoint(x: r.maxX, y: r.maxY),
                IRPoint(x: r.minX, y: r.maxY),
                IRPoint(x: r.minX, y: r.minY),
            ], properties: [])
        }
    }
}
