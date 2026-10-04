/// One exact positive-area scanline rectangle, retaining its source polygon.
public struct RectilinearBand: Equatable, Sendable {
    public let polygonIndex: Int
    public let minX: Int32
    public let maxX: Int32
    public let minY: Int32
    public let maxY: Int32

    /// Reassigns polygon ownership and exactly scales this validated band.
    /// The caller owns polygon semantics and the physical meaning of the ratio.
    /// Multiplication must fit Int64 before division; coordinates are never rounded.
    public func relocated(
        toPolygonIndex polygonIndex: Int,
        coordinateNumerator: Int64,
        coordinateDenominator: Int64
    ) throws -> RectilinearBand {
        guard polygonIndex >= 0, coordinateNumerator > 0, coordinateDenominator > 0 else {
            throw RectilinearDecompositionError.invalidRelocationParameters
        }
        func scaled(_ coordinate: Int32) throws -> Int32 {
            let (product, overflow) = Int64(coordinate).multipliedReportingOverflow(by: coordinateNumerator)
            guard !overflow else {
                throw RectilinearDecompositionError.relocationCoordinateOverflow
            }
            guard product % coordinateDenominator == 0 else {
                throw RectilinearDecompositionError.inexactRelocationCoordinate
            }
            guard let result = Int32(exactly: product / coordinateDenominator) else {
                throw RectilinearDecompositionError.relocatedCoordinateOutOfRange
            }
            return result
        }
        return try RectilinearBand(polygonIndex: polygonIndex,
            minX: scaled(minX), maxX: scaled(maxX), minY: scaled(minY), maxY: scaled(maxY))
    }
}
