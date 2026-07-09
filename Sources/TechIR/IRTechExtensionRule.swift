/// Directional extension rule between two layers.
public struct IRTechExtensionRule: Hashable, Sendable, Codable {
    public enum Direction: String, Hashable, Sendable, Codable {
        case horizontal
        case vertical
    }

    public var extendingLayerName: String
    public var enclosedLayerName: String
    public var minExtension: Double
    public var direction: Direction

    public init(
        extendingLayerName: String,
        enclosedLayerName: String,
        minExtension: Double,
        direction: Direction
    ) {
        self.extendingLayerName = extendingLayerName
        self.enclosedLayerName = enclosedLayerName
        self.minExtension = minExtension
        self.direction = direction
    }
}
