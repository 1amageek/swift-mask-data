import LayoutIR

/// DRC (Design Rule Check) operations on regions.
/// Supports both Manhattan (fast AABB-based) and non-Manhattan (edge-based) checks.
enum DRCCheck {

    /// Check minimum width of each polygon.
    static func widthCheck(_ region: Region, minWidth: Int32, metric: DRCMetric = .euclidean) -> [IREdgePair] {
        let allManhattan = region.polygons.allSatisfy { PolygonUtils.isManhattan($0.points) }

        if allManhattan && metric == .euclidean {
            return widthCheckManhattan(region, minWidth: minWidth)
        }

        return EdgeDRC.widthCheck(region, minWidth: minWidth, metric: metric)
    }

    /// Check minimum spacing between two regions.
    static func spaceCheck(_ a: Region, _ b: Region, minSpace: Int32, metric: DRCMetric = .euclidean) -> [IREdgePair] {
        let allManhattan = a.polygons.allSatisfy { PolygonUtils.isManhattan($0.points) }
                        && b.polygons.allSatisfy { PolygonUtils.isManhattan($0.points) }

        if allManhattan && metric == .euclidean {
            return spaceCheckManhattan(a, b, minSpace: minSpace)
        }

        return EdgeDRC.spaceCheck(a, b, minSpace: minSpace, metric: metric)
    }

    /// Check minimum enclosure of inner region by outer region.
    static func enclosureCheck(outer: Region, inner: Region, minEnclosure: Int32, metric: DRCMetric = .euclidean) -> [IREdgePair] {
        let allManhattan = outer.polygons.allSatisfy { PolygonUtils.isManhattan($0.points) }
                        && inner.polygons.allSatisfy { PolygonUtils.isManhattan($0.points) }

        if allManhattan && metric == .euclidean {
            return enclosureCheckManhattan(outer: outer, inner: inner, minEnclosure: minEnclosure)
        }

        return EdgeDRC.enclosureCheck(outer: outer, inner: inner, minEnclosure: minEnclosure, metric: metric)
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
        var violations: [IREdgePair] = []

        for poly in region.polygons {
            guard let bb = PolygonUtils.boundingBox(of: poly.points) else { continue }

            let width = bb.maxX - bb.minX
            let height = bb.maxY - bb.minY

            if width < minWidth {
                let e1 = IREdge(p1: IRPoint(x: bb.minX, y: bb.minY), p2: IRPoint(x: bb.minX, y: bb.maxY))
                let e2 = IREdge(p1: IRPoint(x: bb.maxX, y: bb.minY), p2: IRPoint(x: bb.maxX, y: bb.maxY))
                violations.append(IREdgePair(edge1: e1, edge2: e2))
            }
            if height < minWidth {
                let e1 = IREdge(p1: IRPoint(x: bb.minX, y: bb.minY), p2: IRPoint(x: bb.maxX, y: bb.minY))
                let e2 = IREdge(p1: IRPoint(x: bb.minX, y: bb.maxY), p2: IRPoint(x: bb.maxX, y: bb.maxY))
                violations.append(IREdgePair(edge1: e1, edge2: e2))
            }
        }

        return violations
    }

    private static func spaceCheckManhattan(_ a: Region, _ b: Region, minSpace: Int32) -> [IREdgePair] {
        var violations: [IREdgePair] = []

        for polyA in a.polygons {
            guard let bbA = PolygonUtils.boundingBox(of: polyA.points) else { continue }

            for polyB in b.polygons {
                guard let bbB = PolygonUtils.boundingBox(of: polyB.points) else { continue }

                let xGap: Int32
                if bbA.maxX <= bbB.minX {
                    xGap = bbB.minX - bbA.maxX
                } else if bbB.maxX <= bbA.minX {
                    xGap = bbA.minX - bbB.maxX
                } else {
                    xGap = 0
                }

                let yGap: Int32
                if bbA.maxY <= bbB.minY {
                    yGap = bbB.minY - bbA.maxY
                } else if bbB.maxY <= bbA.minY {
                    yGap = bbA.minY - bbB.maxY
                } else {
                    yGap = 0
                }

                if xGap > 0 && xGap < minSpace {
                    let overlapMinY = max(bbA.minY, bbB.minY)
                    let overlapMaxY = min(bbA.maxY, bbB.maxY)
                    if overlapMinY < overlapMaxY {
                        let e1 = IREdge(p1: IRPoint(x: bbA.maxX, y: overlapMinY), p2: IRPoint(x: bbA.maxX, y: overlapMaxY))
                        let e2 = IREdge(p1: IRPoint(x: bbB.minX, y: overlapMinY), p2: IRPoint(x: bbB.minX, y: overlapMaxY))
                        violations.append(IREdgePair(edge1: e1, edge2: e2))
                    }
                }
                if yGap > 0 && yGap < minSpace {
                    let overlapMinX = max(bbA.minX, bbB.minX)
                    let overlapMaxX = min(bbA.maxX, bbB.maxX)
                    if overlapMinX < overlapMaxX {
                        let e1 = IREdge(p1: IRPoint(x: overlapMinX, y: bbA.maxY), p2: IRPoint(x: overlapMaxX, y: bbA.maxY))
                        let e2 = IREdge(p1: IRPoint(x: overlapMinX, y: bbB.minY), p2: IRPoint(x: overlapMaxX, y: bbB.minY))
                        violations.append(IREdgePair(edge1: e1, edge2: e2))
                    }
                }
            }
        }

        return violations
    }

    private static func enclosureCheckManhattan(outer: Region, inner: Region, minEnclosure: Int32) -> [IREdgePair] {
        var violations: [IREdgePair] = []

        for innerPoly in inner.polygons {
            guard let bbI = PolygonUtils.boundingBox(of: innerPoly.points) else { continue }

            for outerPoly in outer.polygons {
                guard let bbO = PolygonUtils.boundingBox(of: outerPoly.points) else { continue }

                guard bbO.minX <= bbI.minX && bbO.maxX >= bbI.maxX && bbO.minY <= bbI.minY && bbO.maxY >= bbI.maxY else { continue }

                let leftEnc = bbI.minX - bbO.minX
                let rightEnc = bbO.maxX - bbI.maxX
                let bottomEnc = bbI.minY - bbO.minY
                let topEnc = bbO.maxY - bbI.maxY

                if leftEnc < minEnclosure {
                    let e1 = IREdge(p1: IRPoint(x: bbO.minX, y: bbI.minY), p2: IRPoint(x: bbO.minX, y: bbI.maxY))
                    let e2 = IREdge(p1: IRPoint(x: bbI.minX, y: bbI.minY), p2: IRPoint(x: bbI.minX, y: bbI.maxY))
                    violations.append(IREdgePair(edge1: e1, edge2: e2))
                }
                if rightEnc < minEnclosure {
                    let e1 = IREdge(p1: IRPoint(x: bbI.maxX, y: bbI.minY), p2: IRPoint(x: bbI.maxX, y: bbI.maxY))
                    let e2 = IREdge(p1: IRPoint(x: bbO.maxX, y: bbI.minY), p2: IRPoint(x: bbO.maxX, y: bbI.maxY))
                    violations.append(IREdgePair(edge1: e1, edge2: e2))
                }
                if bottomEnc < minEnclosure {
                    let e1 = IREdge(p1: IRPoint(x: bbI.minX, y: bbO.minY), p2: IRPoint(x: bbI.maxX, y: bbO.minY))
                    let e2 = IREdge(p1: IRPoint(x: bbI.minX, y: bbI.minY), p2: IRPoint(x: bbI.maxX, y: bbI.minY))
                    violations.append(IREdgePair(edge1: e1, edge2: e2))
                }
                if topEnc < minEnclosure {
                    let e1 = IREdge(p1: IRPoint(x: bbI.minX, y: bbI.maxY), p2: IRPoint(x: bbI.maxX, y: bbI.maxY))
                    let e2 = IREdge(p1: IRPoint(x: bbI.minX, y: bbO.maxY), p2: IRPoint(x: bbI.maxX, y: bbO.maxY))
                    violations.append(IREdgePair(edge1: e1, edge2: e2))
                }
            }
        }

        return violations
    }
}
