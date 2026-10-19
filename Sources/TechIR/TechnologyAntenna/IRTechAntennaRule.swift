/// An unqualified legacy ratio, without oxide scope or a diffusion-dependent law.
public struct IRTechAntennaRule: Hashable, Sendable, Codable {
    public var layerName: String
    public var maxRatio: Double

    public init(layerName: String, maxRatio: Double) {
        self.layerName = layerName
        self.maxRatio = maxRatio
    }
}
