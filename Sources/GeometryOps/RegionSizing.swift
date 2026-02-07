import LayoutIR

/// Sizing (grow/shrink) operations on regions.
enum RegionSizing {

    /// Grow (positive amount) or shrink (negative amount) each polygon.
    /// Uses simple bounding-box expansion for Manhattan geometry,
    /// or Minkowski sizing for non-Manhattan.
    static func size(_ region: Region, by amount: Int32, cornerMode: CornerMode = .square) -> Region {
        var result: [IRBoundary] = []

        for poly in region.polygons {
            if PolygonUtils.isManhattan(poly.points) && cornerMode == .square {
                // Fast path for Manhattan + square corners
                if let expanded = sizeManhattan(poly, by: amount, layer: region.layer) {
                    result.append(expanded)
                }
            } else {
                // General path via Minkowski sizing
                let sized = MinkowskiSizing.size(poly, by: amount, cornerMode: cornerMode, layer: region.layer)
                result.append(contentsOf: sized)
            }
        }

        return Region(layer: region.layer, polygons: result)
    }

    private static func sizeManhattan(_ poly: IRBoundary, by amount: Int32, layer: Int16) -> IRBoundary? {
        guard let bb = PolygonUtils.boundingBox(of: poly.points) else { return nil }
        let minX = bb.minX, minY = bb.minY, maxX = bb.maxX, maxY = bb.maxY

        let newMinX = minX - amount
        let newMinY = minY - amount
        let newMaxX = maxX + amount
        let newMaxY = maxY + amount

        guard newMinX < newMaxX && newMinY < newMaxY else { return nil }

        return IRBoundary(layer: layer, datatype: 0, points: [
            IRPoint(x: newMinX, y: newMinY),
            IRPoint(x: newMaxX, y: newMinY),
            IRPoint(x: newMaxX, y: newMaxY),
            IRPoint(x: newMinX, y: newMaxY),
            IRPoint(x: newMinX, y: newMinY),
        ], properties: [])
    }
}
