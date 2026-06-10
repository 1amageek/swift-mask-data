import LayoutIR

/// DRC (Design Rule Check) operations on regions.
/// Supports both Manhattan (scanline band-based) and non-Manhattan (edge-based) checks.
enum DRCCheck {

    /// Check minimum width of each polygon.
    static func widthCheck(_ region: Region, minWidth: Int32, metric: DRCMetric = .euclidean) -> [IREdgePair] {
        let allManhattan = region.polygons.allSatisfy { PolygonGeometry.isManhattan($0.points) }

        if allManhattan && metric == .euclidean {
            return widthCheckManhattan(region, minWidth: minWidth)
        }

        return EdgeDRC.widthCheck(region, minWidth: minWidth, metric: metric)
    }

    /// Check minimum spacing between two regions.
    static func spaceCheck(_ a: Region, _ b: Region, minSpace: Int32, metric: DRCMetric = .euclidean) -> [IREdgePair] {
        let allManhattan = a.polygons.allSatisfy { PolygonGeometry.isManhattan($0.points) }
                        && b.polygons.allSatisfy { PolygonGeometry.isManhattan($0.points) }

        if allManhattan && metric == .euclidean {
            return spaceCheckManhattan(a, b, minSpace: minSpace)
        }

        return EdgeDRC.spaceCheck(a, b, minSpace: minSpace, metric: metric)
    }

    /// Check minimum spacing of a region against itself (net-blind).
    /// Merges the region first so touching or overlapping polygons never flag,
    /// then reports exterior gaps narrower than `minSpace` — including notches
    /// inside a single connected component and diagonal corner gaps.
    static func selfSpaceCheck(_ region: Region, minSpace: Int32, metric: DRCMetric = .euclidean) -> [IREdgePair] {
        let merged = RegionBoolean.perform(.or, region, Region(layer: region.layer))
        let allManhattan = merged.polygons.allSatisfy { PolygonGeometry.isManhattan($0.points) }

        if allManhattan && metric == .euclidean {
            return spaceCheckManhattan(merged, merged, minSpace: minSpace)
        }

        return selfSpaceCheckGeneral(merged, minSpace: minSpace, metric: metric)
    }

    /// Check minimum enclosure of inner region by outer region.
    /// Inner geometry not covered by outer at all is reported as a violation —
    /// it never silently passes.
    static func enclosureCheck(outer: Region, inner: Region, minEnclosure: Int32, metric: DRCMetric = .euclidean) -> [IREdgePair] {
        let uncovered = inner.not(outer)
        var violations = uncovered.polygons.compactMap(uncoveredInnerViolation)

        let covered = uncovered.isEmpty ? inner : inner.and(outer)
        if !covered.isEmpty {
            let allManhattan = outer.polygons.allSatisfy { PolygonGeometry.isManhattan($0.points) }
                            && covered.polygons.allSatisfy { PolygonGeometry.isManhattan($0.points) }

            if allManhattan && metric == .euclidean {
                violations.append(contentsOf: enclosureCheckManhattan(
                    outer: outer, inner: covered, minEnclosure: minEnclosure
                ))
            } else {
                violations.append(contentsOf: EdgeDRC.enclosureCheck(
                    outer: outer, inner: covered, minEnclosure: minEnclosure, metric: metric
                ))
            }
        }

        return uniqueEdgePairs(violations)
    }

    /// Check for notch violations.
    static func notchCheck(_ region: Region, minNotch: Int32, metric: DRCMetric = .euclidean) -> [IREdgePair] {
        EdgeDRC.notchCheck(region, minNotch: minNotch, metric: metric)
    }

    /// Check minimum separation between two regions.
    static func separationCheck(_ a: Region, _ b: Region, minSeparation: Int32, metric: DRCMetric = .euclidean) -> [IREdgePair] {
        EdgeDRC.separationCheck(a, b, minSeparation: minSeparation, metric: metric)
    }

    /// Check grid alignment.
    static func gridCheck(_ region: Region, gridX: Int32, gridY: Int32) -> [IREdgePair] {
        EdgeDRC.gridCheck(region, gridX: gridX, gridY: gridY)
    }

    /// Check allowed edge angles.
    static func angleCheck(_ region: Region, allowedAngles: Set<Int>) -> [IREdgePair] {
        EdgeDRC.angleCheck(region, allowedAngles: allowedAngles)
    }

    // MARK: - Manhattan Fast Path

    private static func widthCheckManhattan(_ region: Region, minWidth: Int32) -> [IREdgePair] {
        // Width must be measured on the union coverage, not on individual
        // polygons: a merged feature is stored as stacked rectangles, and the
        // seam between two stacks would otherwise read as a sliver-thin band.
        var violations = horizontalWidthViolations(
            RegionBoolean.unionBands(region),
            minWidth: minWidth
        )
        let transposedViolations = horizontalWidthViolations(
            RegionBoolean.unionBands(transpose(region)),
            minWidth: minWidth
        ).map(untranspose)
        violations.append(contentsOf: transposedViolations)
        return uniqueEdgePairs(violations)
    }

    private static func horizontalWidthViolations(
        _ bands: [RegionBoolean.Band],
        minWidth: Int32
    ) -> [IREdgePair] {
        var violations: [IREdgePair] = []

        for band in bands {
            let width = band.xMax - band.xMin

            if width > 0 && width < minWidth {
                let e1 = verticalEdge(x: band.xMin, yMin: band.yMin, yMax: band.yMax)
                let e2 = verticalEdge(x: band.xMax, yMin: band.yMin, yMax: band.yMax)
                violations.append(IREdgePair(edge1: e1, edge2: e2))
            }
        }

        return violations
    }

    private static func spaceCheckManhattan(_ a: Region, _ b: Region, minSpace: Int32) -> [IREdgePair] {
        let bandsA = RegionBoolean.decompose(a)
        let bandsB = RegionBoolean.decompose(b)

        var violations = verticalSpaceViolations(bandsA, bandsB, minSpace: minSpace)
        let transposedViolations = verticalSpaceViolations(
            RegionBoolean.decompose(transpose(a)),
            RegionBoolean.decompose(transpose(b)),
            minSpace: minSpace
        ).map(untranspose)
        violations.append(contentsOf: transposedViolations)
        violations.append(contentsOf: cornerSpaceViolations(bandsA, bandsB, minSpace: minSpace))

        return uniqueEdgePairs(violations.map(canonicalized))
    }

    /// Euclidean corner-to-corner spacing between diagonally adjacent bands.
    /// The axis-projection checks only see band pairs overlapping in one axis,
    /// so gaps across a diagonal corner would otherwise pass silently.
    private static func cornerSpaceViolations(
        _ a: [RegionBoolean.Band],
        _ b: [RegionBoolean.Band],
        minSpace: Int32
    ) -> [IREdgePair] {
        var violations: [IREdgePair] = []
        let minSpaceSquared = Int64(minSpace) * Int64(minSpace)
        let grid = BandGrid(bands: b, margin: minSpace)

        for bandA in a {
            for index in grid.candidateIndices(near: bandA, margin: minSpace) {
                let bandB = b[index]
                let dx = max(Int64(bandB.xMin) - Int64(bandA.xMax), Int64(bandA.xMin) - Int64(bandB.xMax))
                let dy = max(Int64(bandB.yMin) - Int64(bandA.yMax), Int64(bandA.yMin) - Int64(bandB.yMax))
                guard dx > 0 && dy > 0 else { continue }
                guard dx * dx + dy * dy < minSpaceSquared else { continue }

                let cornerA = IRPoint(
                    x: Int64(bandB.xMin) - Int64(bandA.xMax) > 0 ? bandA.xMax : bandA.xMin,
                    y: Int64(bandB.yMin) - Int64(bandA.yMax) > 0 ? bandA.yMax : bandA.yMin
                )
                let cornerB = IRPoint(
                    x: Int64(bandB.xMin) - Int64(bandA.xMax) > 0 ? bandB.xMin : bandB.xMax,
                    y: Int64(bandB.yMin) - Int64(bandA.yMax) > 0 ? bandB.yMin : bandB.yMax
                )
                violations.append(IREdgePair(
                    edge1: IREdge(p1: cornerA, p2: cornerA),
                    edge2: IREdge(p1: cornerB, p2: cornerB)
                ))
            }
        }

        return violations
    }

    /// Self-spacing for regions containing non-Manhattan polygons.
    /// Cross-polygon gaps use plain edge distances; same-polygon edge pairs
    /// are only spacing violations when the gap between them is exterior —
    /// interior pairs are the polygon's own width, not spacing.
    private static func selfSpaceCheckGeneral(_ merged: Region, minSpace: Int32, metric: DRCMetric) -> [IREdgePair] {
        var violations: [IREdgePair] = []
        let polys = merged.polygons

        for i in polys.indices {
            let edgesI = PolygonGeometry.edges(of: polys[i].points)

            for j in (i + 1)..<polys.count {
                let edgesJ = PolygonGeometry.edges(of: polys[j].points)
                for ea in edgesI {
                    for eb in edgesJ {
                        let dist = EdgeDRC.edgeDistance(ea, eb, metric: metric)
                        if dist > 0 && dist < Double(minSpace) {
                            violations.append(IREdgePair(edge1: ea, edge2: eb))
                        }
                    }
                }
            }

            guard edgesI.count >= 4 else { continue }
            for a in 0..<edgesI.count {
                guard a + 2 < edgesI.count else { continue }
                for b in (a + 2)..<edgesI.count {
                    if b == edgesI.count - 1 && a == 0 { continue }
                    let dist = EdgeDRC.edgeDistance(edgesI[a], edgesI[b], metric: metric)
                    guard dist > 0 && dist < Double(minSpace) else { continue }
                    let midpoint = closestApproachMidpoint(edgesI[a], edgesI[b])
                    if !PolygonGeometry.contains(midpoint, in: polys[i].points) {
                        violations.append(IREdgePair(edge1: edgesI[a], edge2: edgesI[b]))
                    }
                }
            }
        }

        return uniqueEdgePairs(violations)
    }

    /// Midpoint of the closest approach between two segments — used to decide
    /// whether the gap between same-polygon edges is interior or exterior.
    private static func closestApproachMidpoint(_ e1: IREdge, _ e2: IREdge) -> IRPoint {
        var bestDistance = Double.infinity
        var bestA = (Double(e1.p1.x), Double(e1.p1.y))
        var bestB = (Double(e2.p1.x), Double(e2.p1.y))

        for p in [e1.p1, e1.p2] {
            let q = closestPoint(on: e2, to: p)
            let candidate = (Double(p.x), Double(p.y))
            let d = squaredDistance(candidate, q)
            if d < bestDistance {
                bestDistance = d
                bestA = candidate
                bestB = q
            }
        }
        for p in [e2.p1, e2.p2] {
            let q = closestPoint(on: e1, to: p)
            let candidate = (Double(p.x), Double(p.y))
            let d = squaredDistance(candidate, q)
            if d < bestDistance {
                bestDistance = d
                bestA = q
                bestB = candidate
            }
        }

        return IRPoint(
            x: Int32(((bestA.0 + bestB.0) / 2).rounded()),
            y: Int32(((bestA.1 + bestB.1) / 2).rounded())
        )
    }

    private static func closestPoint(on edge: IREdge, to point: IRPoint) -> (Double, Double) {
        let x1 = Double(edge.p1.x), y1 = Double(edge.p1.y)
        let x2 = Double(edge.p2.x), y2 = Double(edge.p2.y)
        let px = Double(point.x), py = Double(point.y)
        let dx = x2 - x1, dy = y2 - y1
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return (x1, y1) }
        let t = max(0, min(1, ((px - x1) * dx + (py - y1) * dy) / lengthSquared))
        return (x1 + t * dx, y1 + t * dy)
    }

    private static func squaredDistance(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let dx = b.0 - a.0
        let dy = b.1 - a.1
        return dx * dx + dy * dy
    }

    /// Orders the edges of a pair canonically so that mirrored duplicates
    /// from symmetric checks (self-spacing) collapse in `uniqueEdgePairs`.
    private static func canonicalized(_ pair: IREdgePair) -> IREdgePair {
        if edgeKey(pair.edge2) < edgeKey(pair.edge1) {
            return IREdgePair(edge1: pair.edge2, edge2: pair.edge1)
        }
        return pair
    }

    private static func edgeKey(_ edge: IREdge) -> (Int32, Int32, Int32, Int32) {
        (edge.p1.x, edge.p1.y, edge.p2.x, edge.p2.y)
    }

    private static func verticalSpaceViolations(
        _ a: [RegionBoolean.Band],
        _ b: [RegionBoolean.Band],
        minSpace: Int32
    ) -> [IREdgePair] {
        var violations: [IREdgePair] = []
        let grid = BandGrid(bands: b, margin: minSpace)

        for bandA in a {
            for index in grid.candidateIndices(near: bandA, margin: minSpace) {
                let bandB = b[index]
                let overlapMinY = max(bandA.yMin, bandB.yMin)
                let overlapMaxY = min(bandA.yMax, bandB.yMax)
                guard overlapMinY < overlapMaxY else { continue }

                if bandA.xMax <= bandB.xMin {
                    let gap = bandB.xMin - bandA.xMax
                    if gap > 0 && gap < minSpace {
                        let e1 = verticalEdge(x: bandA.xMax, yMin: overlapMinY, yMax: overlapMaxY)
                        let e2 = verticalEdge(x: bandB.xMin, yMin: overlapMinY, yMax: overlapMaxY)
                        violations.append(IREdgePair(edge1: e1, edge2: e2))
                    }
                }
                if bandB.xMax <= bandA.xMin {
                    let gap = bandA.xMin - bandB.xMax
                    if gap > 0 && gap < minSpace {
                        let e1 = verticalEdge(x: bandA.xMin, yMin: overlapMinY, yMax: overlapMaxY)
                        let e2 = verticalEdge(x: bandB.xMax, yMin: overlapMinY, yMax: overlapMaxY)
                        violations.append(IREdgePair(edge1: e1, edge2: e2))
                    }
                }
            }
        }

        return violations
    }

    /// Marks an inner polygon that lies outside the outer region entirely.
    /// Reported as the pair of opposite bounding-box edges so downstream
    /// consumers see the full uncovered extent.
    private static func uncoveredInnerViolation(_ polygon: IRBoundary) -> IREdgePair? {
        guard let bb = PolygonGeometry.boundingBox(of: polygon.points) else { return nil }
        return IREdgePair(
            edge1: verticalEdge(x: bb.minX, yMin: bb.minY, yMax: bb.maxY),
            edge2: verticalEdge(x: bb.maxX, yMin: bb.minY, yMax: bb.maxY)
        )
    }

    private static func enclosureCheckManhattan(outer: Region, inner: Region, minEnclosure: Int32) -> [IREdgePair] {
        var violations = verticalEnclosureViolations(
            outerBands: RegionBoolean.decompose(outer),
            innerBands: RegionBoolean.decompose(inner),
            minEnclosure: minEnclosure
        )
        let transposedViolations = verticalEnclosureViolations(
            outerBands: RegionBoolean.decompose(transpose(outer)),
            innerBands: RegionBoolean.decompose(transpose(inner)),
            minEnclosure: minEnclosure
        ).map(untranspose)
        violations.append(contentsOf: transposedViolations)

        return uniqueEdgePairs(violations)
    }

    private static func verticalEnclosureViolations(
        outerBands: [RegionBoolean.Band],
        innerBands: [RegionBoolean.Band],
        minEnclosure: Int32
    ) -> [IREdgePair] {
        var violations: [IREdgePair] = []

        ScanlineSweep.sweepRows(outerBands, innerBands) { yMin, yMax, outerIntervals, innerIntervals in
            guard !innerIntervals.isEmpty else { return }
            let outerUnion = RegionBoolean.unionIntervals(outerIntervals)

            for inner in innerIntervals {
                guard let outerInterval = coveringInterval(of: inner, in: outerUnion) else {
                    continue
                }

                let leftEnclosure = inner.lo - outerInterval.lo
                if leftEnclosure < minEnclosure {
                    let e1 = verticalEdge(x: outerInterval.lo, yMin: yMin, yMax: yMax)
                    let e2 = verticalEdge(x: inner.lo, yMin: yMin, yMax: yMax)
                    violations.append(IREdgePair(edge1: e1, edge2: e2))
                }

                let rightEnclosure = outerInterval.hi - inner.hi
                if rightEnclosure < minEnclosure {
                    let e1 = verticalEdge(x: inner.hi, yMin: yMin, yMax: yMax)
                    let e2 = verticalEdge(x: outerInterval.hi, yMin: yMin, yMax: yMax)
                    violations.append(IREdgePair(edge1: e1, edge2: e2))
                }
            }
        }

        return violations
    }

    /// The unique interval of a disjoint sorted union that can contain
    /// `inner`: the last one starting at or before `inner.lo`. Intervals
    /// before it end strictly left of it, intervals after start to its right.
    private static func coveringInterval(
        of inner: RegionBoolean.Interval,
        in sortedUnion: [RegionBoolean.Interval]
    ) -> RegionBoolean.Interval? {
        var low = 0
        var high = sortedUnion.count
        while low < high {
            let mid = (low + high) / 2
            if sortedUnion[mid].lo <= inner.lo {
                low = mid + 1
            } else {
                high = mid
            }
        }
        guard low > 0 else { return nil }
        let candidate = sortedUnion[low - 1]
        return candidate.hi >= inner.hi ? candidate : nil
    }

    private static func verticalEdge(x: Int32, yMin: Int32, yMax: Int32) -> IREdge {
        IREdge(p1: IRPoint(x: x, y: yMin), p2: IRPoint(x: x, y: yMax))
    }

    private static func transpose(_ region: Region) -> Region {
        Region(layer: region.layer, polygons: region.polygons.map { polygon in
            IRBoundary(
                layer: polygon.layer,
                datatype: polygon.datatype,
                points: polygon.points.map { IRPoint(x: $0.y, y: $0.x) },
                properties: polygon.properties
            )
        })
    }

    private static func untranspose(_ pair: IREdgePair) -> IREdgePair {
        IREdgePair(edge1: untranspose(pair.edge1), edge2: untranspose(pair.edge2))
    }

    private static func untranspose(_ edge: IREdge) -> IREdge {
        IREdge(
            p1: IRPoint(x: edge.p1.y, y: edge.p1.x),
            p2: IRPoint(x: edge.p2.y, y: edge.p2.x)
        )
    }

    private static func uniqueEdgePairs(_ pairs: [IREdgePair]) -> [IREdgePair] {
        var seen: Set<IREdgePair> = []
        var result: [IREdgePair] = []
        for pair in pairs where seen.insert(pair).inserted {
            result.append(pair)
        }
        return result
    }
}
