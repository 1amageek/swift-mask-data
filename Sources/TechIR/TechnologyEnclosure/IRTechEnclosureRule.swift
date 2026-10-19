/// Enclosure rule between two layers.
public struct IRTechEnclosureRule: Hashable, Sendable, Codable {
    public var outerLayerName: String
    public var innerLayerName: String
    public var minEnclosure: Double

    public init(outerLayerName: String, innerLayerName: String, minEnclosure: Double) {
        self.outerLayerName = outerLayerName
        self.innerLayerName = innerLayerName
        self.minEnclosure = minEnclosure
    }
}
