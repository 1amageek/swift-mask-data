/// Design rules for a specific layer.
public struct IRTechDesignRule: Hashable, Sendable, Codable {
    public var layerName: String
    public var minWidth: Double?
    public var minSpacing: Double?
    public var minArea: Double?
    public var minDensity: Double?
    public var maxDensity: Double?

    public init(
        layerName: String,
        minWidth: Double? = nil,
        minSpacing: Double? = nil,
        minArea: Double? = nil,
        minDensity: Double? = nil,
        maxDensity: Double? = nil
    ) {
        self.layerName = layerName
        self.minWidth = minWidth
        self.minSpacing = minSpacing
        self.minArea = minArea
        self.minDensity = minDensity
        self.maxDensity = maxDensity
    }
}
