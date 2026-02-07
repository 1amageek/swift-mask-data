public struct IRCellRef: Hashable, Sendable, Codable {
    public var cellName: String
    public var origin: IRPoint
    public var transform: IRTransform
    public var properties: [IRProperty]

    public init(
        cellName: String,
        origin: IRPoint,
        transform: IRTransform = .identity,
        properties: [IRProperty] = []
    ) {
        self.cellName = cellName
        self.origin = origin
        self.transform = transform
        self.properties = properties
    }
}
