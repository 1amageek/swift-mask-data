public struct IRText: Hashable, Sendable, Codable {
    public var layer: Int16
    public var texttype: Int16
    public var transform: IRTransform
    public var position: IRPoint
    public var string: String
    public var properties: [IRProperty]

    public init(
        layer: Int16,
        texttype: Int16 = 0,
        transform: IRTransform = .identity,
        position: IRPoint,
        string: String,
        properties: [IRProperty] = []
    ) {
        self.layer = layer
        self.texttype = texttype
        self.transform = transform
        self.position = position
        self.string = string
        self.properties = properties
    }
}
