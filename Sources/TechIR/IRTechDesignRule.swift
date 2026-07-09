/// Design rules for a specific layer.
public struct IRTechDesignRule: Hashable, Sendable, Codable {
    public var layerName: String
    public var minWidth: Double?
    public var minSpacing: Double?
    public var minArea: Double?
    public var minEnclosedArea: Double?
    public var minDensity: Double?
    public var maxDensity: Double?
    public var requiresRectangular: Bool?
    public var allowedAngleStepDegrees: Double?

    public init(
        layerName: String,
        minWidth: Double? = nil,
        minSpacing: Double? = nil,
        minArea: Double? = nil,
        minEnclosedArea: Double? = nil,
        minDensity: Double? = nil,
        maxDensity: Double? = nil,
        requiresRectangular: Bool? = nil,
        allowedAngleStepDegrees: Double? = nil
    ) {
        self.layerName = layerName
        self.minWidth = minWidth
        self.minSpacing = minSpacing
        self.minArea = minArea
        self.minEnclosedArea = minEnclosedArea
        self.minDensity = minDensity
        self.maxDensity = maxDensity
        self.requiresRectangular = requiresRectangular
        self.allowedAngleStepDegrees = allowedAngleStepDegrees
    }
}
