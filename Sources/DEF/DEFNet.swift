import LayoutIR

public struct DEFNet: Hashable, Sendable, Codable {
    public var name: String
    public var connections: [DEFConnection]
    public var use: DEFSpecialNet.NetUse?
    public var routing: [DEFRouteWire]
    public var properties: [DEFProperty]

    public init(name: String, connections: [DEFConnection] = [],
                use: DEFSpecialNet.NetUse? = nil,
                routing: [DEFRouteWire] = [],
                properties: [DEFProperty] = []) {
        self.name = name
        self.connections = connections
        self.use = use
        self.routing = routing
        self.properties = properties
    }
}

public struct DEFConnection: Hashable, Sendable, Codable {
    public var componentName: String
    public var pinName: String

    public init(componentName: String, pinName: String) {
        self.componentName = componentName
        self.pinName = pinName
    }
}

/// A regular net routing wire.
public struct DEFRouteWire: Hashable, Sendable, Codable {
    public var status: RouteStatus
    public var layerName: String
    public var points: [IRPoint]
    /// Per-point extensions in DEF DBU; an empty array means every extension is omitted.
    public var pointExtensions: [Int32?]
    public var viaName: String?
    public var viaOrientation: DEFOrientation
    public var taper: Bool
    public var style: Int?

    public enum RouteStatus: String, Hashable, Sendable, Codable {
        case routed = "ROUTED"
        case fixed = "FIXED"
        case cover = "COVER"
        case noshield = "NOSHIELD"
        case new_ = "NEW"
    }

    public init(status: RouteStatus = .routed, layerName: String,
                points: [IRPoint] = [], viaName: String? = nil,
                taper: Bool = false, style: Int? = nil, pointExtensions: [Int32?] = [], viaOrientation: DEFOrientation = .n) {
        self.status = status
        self.layerName = layerName
        self.points = points
        self.viaName = viaName
        self.viaOrientation = viaOrientation
        self.pointExtensions = pointExtensions
        self.taper = taper
        self.style = style
    }
}
