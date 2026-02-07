public struct IRBoundary: Hashable, Sendable, Codable {
    public var layer: Int16
    public var datatype: Int16
    /// Closed polygon vertices. First and last points must be identical.
    public var points: [IRPoint]
    public var properties: [IRProperty]

    public init(
        layer: Int16,
        datatype: Int16,
        points: [IRPoint],
        properties: [IRProperty] = []
    ) {
        self.layer = layer
        self.datatype = datatype
        self.points = points
        self.properties = properties
    }
}
