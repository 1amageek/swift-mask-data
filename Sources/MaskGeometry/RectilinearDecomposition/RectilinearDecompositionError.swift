public enum RectilinearDecompositionError: Error, Equatable, Sendable {
    public enum Resource: Equatable, Sendable {
        case inputEntries, edgeProbes, intermediateBands, sweepWork, outputBands
    }

    case invalidLimits
    case invalidUnionPolygonIndex
    case invalidRelocationParameters
    case relocationCoordinateOverflow
    case inexactRelocationCoordinate
    case relocatedCoordinateOutOfRange
    case unsupportedNonManhattanGeometry(polygonIndex: Int)
    case limitExceeded(Resource)
    case cancelled
}
