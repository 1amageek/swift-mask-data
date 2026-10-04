public enum RectilinearDecompositionError: Error, Equatable, Sendable {
    public enum Resource: Equatable, Sendable {
        case inputEntries, edgeProbes, outputBands
    }

    case invalidLimits
    case invalidRelocationParameters
    case relocationCoordinateOverflow
    case inexactRelocationCoordinate
    case relocatedCoordinateOutOfRange
    case unsupportedNonManhattanGeometry(polygonIndex: Int)
    case limitExceeded(Resource)
    case cancelled
}
