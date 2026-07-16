import LayoutIR

/// Connectivity analysis on regions: connected components, enclosed holes,
/// and point containment.
enum RegionConnectivity {

    /// Groups the region's polygons into connected components.
    /// Two Manhattan polygons belong to the same component when they overlap
    /// or share a boundary segment of positive length; corner-only contact
    /// does not connect. Non-Manhattan polygons each form their own component
    /// (merge the region first so overlapping ones are already unified).
    static func connectedComponents(of region: Region) -> [Region] {
        let polys = region.polygons
        guard polys.count > 1 else {
            return polys.isEmpty ? [] : [region]
        }

        let bandsPerPolygon: [[RegionBoolean.Band]] = polys.map { poly in
            guard PolygonGeometry.isManhattan(poly.points) else { return [] }
            return RegionBoolean.decompose(Region(layer: region.layer, polygons: [poly]))
        }

        var parent = Array(0..<polys.count)
        func find(_ index: Int) -> Int {
            var root = index
            while parent[root] != root { root = parent[root] }
            var node = index
            while parent[node] != root {
                let next = parent[node]
                parent[node] = root
                node = next
            }
            return root
        }
        func union(_ i: Int, _ j: Int) {
            let rootI = find(i)
            let rootJ = find(j)
            if rootI != rootJ { parent[rootI] = rootJ }
        }

        // Touching requires bounding boxes at zero separation, so a spatial
        // index over the boxes prunes the pair scan to geometric neighbours.
        let boxes: [RegionBoolean.Band] = polys.map { poly in
            guard let bb = PolygonGeometry.boundingBox(of: poly.points) else {
                return RegionBoolean.Band(xMin: 0, xMax: 0, yMin: 0, yMax: 0)
            }
            return RegionBoolean.Band(xMin: bb.minX, xMax: bb.maxX, yMin: bb.minY, yMax: bb.maxY)
        }
        let grid = BandGrid(bands: boxes, margin: 1)
        for i in 0..<polys.count {
            for j in grid.candidateIndices(near: boxes[i], margin: 1) where j > i {
                guard find(i) != find(j) else { continue }
                if polygonsTouch(bandsPerPolygon[i], bandsPerPolygon[j]) {
                    union(i, j)
                }
            }
        }

        var componentOrder: [Int] = []
        var members: [Int: [IRBoundary]] = [:]
        for i in 0..<polys.count {
            let root = find(i)
            if members[root] == nil { componentOrder.append(root) }
            members[root, default: []].append(polys[i])
        }

        return componentOrder.map { root in
            Region(layer: region.layer, polygons: members[root] ?? [])
        }
    }

    /// Returns the enclosed holes of the region as filled regions.
    /// A hole is a connected component of the complement that does not reach
    /// the exterior frame surrounding the region's bounding box.
    static func holes(of region: Region) throws -> [Region] {
        guard let bb = region.boundingBox else { return [] }
        let frame = Region(layer: region.layer, polygons: [rectangleBoundary(
            xMin: bb.minX - 1,
            yMin: bb.minY - 1,
            xMax: bb.maxX + 1,
            yMax: bb.maxY + 1,
            layer: region.layer
        )])
        let complement = try frame.subtracting(region)
        return connectedComponents(of: complement).filter { component in
            guard let cb = component.boundingBox else { return false }
            return cb.minX > bb.minX - 1 && cb.minY > bb.minY - 1
                && cb.maxX < bb.maxX + 1 && cb.maxY < bb.maxY + 1
        }
    }

    /// Boundary-inclusive point containment test.
    /// Manhattan polygons use exact band containment; non-Manhattan polygons
    /// fall back to ray casting.
    static func contains(_ region: Region, point: IRPoint) -> Bool {
        for poly in region.polygons {
            if PolygonGeometry.isManhattan(poly.points) {
                let bands = RegionBoolean.decompose(Region(layer: region.layer, polygons: [poly]))
                for band in bands {
                    if band.xMin <= point.x && point.x <= band.xMax
                        && band.yMin <= point.y && point.y <= band.yMax {
                        return true
                    }
                }
            } else if PolygonGeometry.contains(point, in: poly.points) {
                return true
            }
        }
        return false
    }

    private static func polygonsTouch(
        _ a: [RegionBoolean.Band],
        _ b: [RegionBoolean.Band]
    ) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        for bandA in a {
            for bandB in b where bandsTouch(bandA, bandB) {
                return true
            }
        }
        return false
    }

    /// Bands touch when they overlap or share an edge segment of positive
    /// length. Corner-only contact (both overlaps zero) does not connect.
    private static func bandsTouch(_ a: RegionBoolean.Band, _ b: RegionBoolean.Band) -> Bool {
        let xOverlap = Int64(min(a.xMax, b.xMax)) - Int64(max(a.xMin, b.xMin))
        let yOverlap = Int64(min(a.yMax, b.yMax)) - Int64(max(a.yMin, b.yMin))
        if xOverlap > 0 && yOverlap >= 0 { return true }
        if xOverlap >= 0 && yOverlap > 0 { return true }
        return false
    }

    private static func rectangleBoundary(
        xMin: Int32,
        yMin: Int32,
        xMax: Int32,
        yMax: Int32,
        layer: Int16
    ) -> IRBoundary {
        IRBoundary(layer: layer, datatype: 0, points: [
            IRPoint(x: xMin, y: yMin),
            IRPoint(x: xMax, y: yMin),
            IRPoint(x: xMax, y: yMax),
            IRPoint(x: xMin, y: yMax),
            IRPoint(x: xMin, y: yMin),
        ], properties: [])
    }
}
