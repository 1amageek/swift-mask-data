import LayoutIR

extension Region {
    /// Exact cross-polygon coverage, sharing admission across all caller invocations.
    public func rectilinearUnionBands(
        toPolygonIndex polygonIndex: Int,
        budget: inout RectilinearUnionBudget,
        isCancelled: () -> Bool = { false }
    ) throws -> [RectilinearBand] {
        guard polygonIndex >= 0 else { throw RectilinearDecompositionError.invalidUnionPolygonIndex }
        func checkCancellation() throws {
            if isCancelled() { throw RectilinearDecompositionError.cancelled }
        }
        try checkCancellation()
        var bands: [RegionBoolean.Band] = []
        try forEachRectilinearBand(chargeInput: { try budget.spend(.inputEntries, amount: $0) },
            chargeEdge: {
                try checkCancellation()
                try budget.spend(.edgeProbes)
            }, emitBand: { _, band in
                try checkCancellation()
                try budget.spend(.intermediateBands)
                bands.append(band)
            }, checkCancellation: checkCancellation)
        let union = try RegionBoolean.unionBands(bands, chargeWork: {
            try checkCancellation()
            try budget.spend(.sweepWork)
        }, admitRow: {
            try checkCancellation()
            try budget.spend(.outputBands)
        }, checkCancellation: checkCancellation)
        try checkCancellation()
        var result: [RectilinearBand] = []
        result.reserveCapacity(union.count)
        for band in union {
            try checkCancellation()
            result.append(RectilinearBand(polygonIndex: polygonIndex,
                minX: band.xMin, maxX: band.xMax, minY: band.yMin, maxY: band.yMax))
        }
        try checkCancellation()
        return result
    }
}
