import LayoutIR

/// Sizing (grow/shrink) operations on regions.
enum RegionSizing {

    /// Grow (positive amount) or shrink (negative amount) a region.
    /// Manhattan geometry with square corners uses exact band-based
    /// dilation/erosion; other inputs use Minkowski sizing per polygon.
    static func size(_ region: Region, by amount: Int32, cornerMode: CornerMode = .square) throws -> Region {
        guard amount != 0 else { return region }
        guard !region.polygons.isEmpty else { return Region(layer: region.layer) }

        let allManhattan = region.polygons.allSatisfy { PolygonGeometry.isManhattan($0.points) }
        if allManhattan && cornerMode == .square {
            if amount > 0 {
                return try dilateManhattan(region, by: amount)
            }
            return try erodeManhattan(region, by: -amount)
        }

        var result: [IRBoundary] = []
        for poly in region.polygons {
            let sized = MinkowskiSizing.size(poly, by: amount, cornerMode: cornerMode, layer: region.layer)
            result.append(contentsOf: sized)
        }
        return Region(layer: region.layer, polygons: result)
    }

    /// Exact Manhattan dilation: dilation distributes over union, and the
    /// square-corner dilation of an axis-aligned rectangle is the expanded
    /// rectangle. Decomposing to bands first keeps this exact for arbitrary
    /// rectilinear polygons (per-polygon bounding-box expansion would fill
    /// concavities).
    private static func dilateManhattan(_ region: Region, by amount: Int32) throws -> Region {
        let bands = RegionBoolean.decompose(region)
        let expanded = bands.map { band in
            rectangleBoundary(
                xMin: band.xMin - amount,
                yMin: band.yMin - amount,
                xMax: band.xMax + amount,
                yMax: band.yMax + amount,
                layer: region.layer
            )
        }
        return try Region(layer: region.layer, polygons: expanded)
            .union(Region(layer: region.layer))
    }

    /// Exact Manhattan erosion via complement: erode(A) = A − dilate(frame − A).
    /// The frame extends one unit beyond the bounding box so the exterior
    /// complement reaches every outer boundary.
    private static func erodeManhattan(_ region: Region, by amount: Int32) throws -> Region {
        guard let bb = region.boundingBox else { return Region(layer: region.layer) }
        let frame = Region(layer: region.layer, polygons: [rectangleBoundary(
            xMin: bb.minX - 1,
            yMin: bb.minY - 1,
            xMax: bb.maxX + 1,
            yMax: bb.maxY + 1,
            layer: region.layer
        )])
        let complement = try frame.subtracting(region)
        guard !complement.isEmpty else { return region }
        let dilatedComplement = try dilateManhattan(complement, by: amount)
        return try region.subtracting(dilatedComplement)
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
