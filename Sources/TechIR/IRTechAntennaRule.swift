/// Antenna effect rule for a layer.
public struct IRTechAntennaRule: Hashable, Sendable, Codable {
    public var layerName: String
    public var maxRatio: Double

    public init(layerName: String, maxRatio: Double) {
        self.layerName = layerName
        self.maxRatio = maxRatio
    }
}
