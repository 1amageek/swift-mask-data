public struct IRPath: Hashable, Sendable, Codable {
    public var layer: Int16
    public var datatype: Int16
    public var pathType: IRPathType
    /// Width in database units.
    public var width: Int32
    /// Open polyline vertices.
    public var points: [IRPoint]
    public var properties: [IRProperty]
    /// Begin extension in database units (for `customExtension` pathtype).
    public var beginExtension: Int32?
    /// End extension in database units (for `customExtension` pathtype).
    public var endExtension: Int32?

    public init(
        layer: Int16,
        datatype: Int16,
        pathType: IRPathType = .flush,
        width: Int32 = 0,
        points: [IRPoint],
        properties: [IRProperty] = [],
        beginExtension: Int32? = nil,
        endExtension: Int32? = nil
    ) {
        self.layer = layer
        self.datatype = datatype
        self.pathType = pathType
        self.width = width
        self.points = points
        self.properties = properties
        self.beginExtension = beginExtension
        self.endExtension = endExtension
    }
}
