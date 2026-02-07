import LayoutIR

/// Boolean operations on regions using scanline decomposition (Manhattan)
/// or edge processor (non-Manhattan).
enum RegionBoolean {

    static func perform(_ op: BooleanOp, _ a: Region, _ b: Region) -> Region {
        // Check if all polygons are Manhattan
        let allManhattan = a.polygons.allSatisfy { PolygonUtils.isManhattan($0.points) }
                        && b.polygons.allSatisfy { PolygonUtils.isManhattan($0.points) }

        if allManhattan {
            return performManhattan(op, a, b)
        } else {
            return performGeneral(op, a, b)
        }
    }

    // MARK: - Manhattan Path (scanline decomposition)

    private static func performManhattan(_ op: BooleanOp, _ a: Region, _ b: Region) -> Region {
        let bandsA = decompose(a)
        let bandsB = decompose(b)

        var ys = Set<Int32>()
        for band in bandsA { ys.insert(band.yMin); ys.insert(band.yMax) }
        for band in bandsB { ys.insert(band.yMin); ys.insert(band.yMax) }
        let sortedYs = ys.sorted()

        guard sortedYs.count >= 2 else {
            return Region(layer: a.layer)
        }

        var resultBands: [Band] = []

        for yi in 0..<(sortedYs.count - 1) {
            let yMin = sortedYs[yi]
            let yMax = sortedYs[yi + 1]

            let intervalsA = xIntervals(bandsA, at: yMin, yMax: yMax)
            let intervalsB = xIntervals(bandsB, at: yMin, yMax: yMax)

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

    private static func performGeneral(_ op: BooleanOp, _ a: Region, _ b: Region) -> Region {
        let result = EdgeProcessor.booleanOp(op, a: a.polygons, b: b.polygons, layer: a.layer)
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
            guard let bb = PolygonUtils.boundingBox(of: poly.points) else { continue }
            bands.append(Band(xMin: bb.minX, xMax: bb.maxX, yMin: bb.minY, yMax: bb.maxY))
        }
        return bands
    }

    static func xIntervals(_ bands: [Band], at yMin: Int32, yMax: Int32) -> [Interval] {
        bands.compactMap { band in
            if band.yMin <= yMin && band.yMax >= yMax {
                return Interval(lo: band.xMin, hi: band.xMax)
            }
            return nil
        }
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
            guard let bb = PolygonUtils.boundingBox(of: poly.points) else { return nil }
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
