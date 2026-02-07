public struct DEFPin: Hashable, Sendable, Codable {
    public var name: String
    public var direction: Direction?
    public var netName: String?
    public var layerName: String?
    public var x: Int32
    public var y: Int32
    public var orientation: DEFOrientation
    public var placementStatus: DEFComponent.PlacementStatus?
    public var use: DEFSpecialNet.NetUse?
    public var layerRects: [DEFPinLayerRect]
    public var special: Bool
    public var properties: [DEFProperty]

    public enum Direction: String, Hashable, Sendable, Codable {
        case input = "INPUT"
        case output = "OUTPUT"
        case inout_ = "INOUT"
        case feedthru = "FEEDTHRU"
    }

    public init(name: String, direction: Direction? = nil, netName: String? = nil,
                layerName: String? = nil, x: Int32 = 0, y: Int32 = 0,
                orientation: DEFOrientation = .n,
                placementStatus: DEFComponent.PlacementStatus? = nil,
                use: DEFSpecialNet.NetUse? = nil,
                layerRects: [DEFPinLayerRect] = [],
                special: Bool = false,
                properties: [DEFProperty] = []) {
        self.name = name
        self.direction = direction
        self.netName = netName
        self.layerName = layerName
        self.x = x
        self.y = y
        self.orientation = orientation
        self.placementStatus = placementStatus
        self.use = use
        self.layerRects = layerRects
        self.special = special
        self.properties = properties
    }
}

/// Layer geometry for a DEF pin.
public struct DEFPinLayerRect: Hashable, Sendable, Codable {
    public var layerName: String
    public var rects: [DEFRect]

    public init(layerName: String, rects: [DEFRect] = []) {
        self.layerName = layerName
        self.rects = rects
    }
}
