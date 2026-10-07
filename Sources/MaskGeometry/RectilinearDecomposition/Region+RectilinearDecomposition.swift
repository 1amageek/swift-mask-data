import LayoutIR

extension Region {
    /// Decomposes each rectilinear polygon using the same exact kernel as booleans.
    /// Bands preserve polygon identity; overlap across polygons is not removed.
    public func rectilinearBands(
        limits: RectilinearDecompositionLimits = .default,
        isCancelled: () -> Bool = { false }
    ) throws -> [RectilinearBand] {
        guard limits.maximumInputEntries >= 0, limits.maximumEdgeProbes >= 0,
              limits.maximumOutputBands >= 0 else {
            throw RectilinearDecompositionError.invalidLimits
        }
        func checkCancellation() throws {
            if isCancelled() { throw RectilinearDecompositionError.cancelled }
        }
        try checkCancellation()
        var remainingInput = limits.maximumInputEntries
        var remainingProbes = limits.maximumEdgeProbes
        var output: [RectilinearBand] = []
        try forEachRectilinearBand(chargeInput: { count in
            guard count <= remainingInput else {
                throw RectilinearDecompositionError.limitExceeded(.inputEntries)
            }
            remainingInput -= count
        }, chargeEdge: {
            try checkCancellation()
            guard remainingProbes > 0 else {
                throw RectilinearDecompositionError.limitExceeded(.edgeProbes)
            }
            remainingProbes -= 1
        }, emitBand: { polygonIndex, band in
            try checkCancellation()
            guard output.count < limits.maximumOutputBands else {
                throw RectilinearDecompositionError.limitExceeded(.outputBands)
            }
            output.append(RectilinearBand(polygonIndex: polygonIndex,
                minX: band.xMin, maxX: band.xMax, minY: band.yMin, maxY: band.yMax))
        }, checkCancellation: checkCancellation)
        try checkCancellation()
        return output
    }

    /// One admission and decomposition traversal for both public bounded operations.
    func forEachRectilinearBand(
        chargeInput: (Int) throws -> Void,
        chargeEdge: () throws -> Void,
        emitBand: (Int, RegionBoolean.Band) throws -> Void,
        checkCancellation: () throws -> Void
    ) throws {
        for (polygonIndex, polygon) in polygons.enumerated() {
            try checkCancellation()
            guard polygon.points.count < Int.max else {
                throw RectilinearDecompositionError.limitExceeded(.inputEntries)
            }
            try chargeInput(polygon.points.count + 1)
            for index in polygon.points.indices {
                try checkCancellation()
                let next = index == polygon.points.count - 1 ? 0 : index + 1
                let first = polygon.points[index], second = polygon.points[next]
                guard first.x == second.x || first.y == second.y else {
                    throw RectilinearDecompositionError.unsupportedNonManhattanGeometry(polygonIndex: polygonIndex)
                }
            }
            try RegionBoolean.decompose(polygon, chargeEdge: chargeEdge, emitBand: { band in
                try emitBand(polygonIndex, band)
            }, checkCancellation: checkCancellation)
        }
    }
}
