/// One exact positive-area scanline rectangle, retaining its source polygon.
public struct RectilinearBand: Equatable, Sendable {
    public let polygonIndex: Int
    public let minX: Int32
    public let maxX: Int32
    public let minY: Int32
    public let maxY: Int32
}
