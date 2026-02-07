import LayoutIR

public struct DEFSpecialNet: Hashable, Sendable, Codable {
    public var name: String
    public var connections: [DEFConnection]
    public var use: NetUse?
    public var routing: [DEFRouteSegment]
    public var source: String?
    public var weight: Int?
    public var properties: [DEFProperty]

    public enum NetUse: String, Hashable, Sendable, Codable {
        case power = "POWER"
        case ground = "GROUND"
        case signal = "SIGNAL"
        case clock = "CLOCK"
        case reset = "RESET"
        case scan = "SCAN"
        case tieoff = "TIEOFF"
        case analog = "ANALOG"
    }

    public init(name: String, connections: [DEFConnection] = [],
                use: NetUse? = nil, routing: [DEFRouteSegment] = [],
                source: String? = nil, weight: Int? = nil,
                properties: [DEFProperty] = []) {
        self.name = name
        self.connections = connections
        self.use = use
        self.routing = routing
        self.source = source
        self.weight = weight
        self.properties = properties
    }
}

public struct DEFRouteSegment: Hashable, Sendable, Codable {
    public var status: RouteStatus
    public var layerName: String
    public var width: Int32
    public var points: [DEFRoutePoint]
    public var shape: RouteShape?

    public enum RouteStatus: String, Hashable, Sendable, Codable {
        case routed = "ROUTED"
        case fixed = "FIXED"
        case cover = "COVER"
        case shield = "SHIELD"
        case new_ = "NEW"
    }

    public enum RouteShape: String, Hashable, Sendable, Codable {
        case ring = "RING"
        case padring = "PADRING"
        case blockring = "BLOCKRING"
        case stripe = "STRIPE"
        case followpin = "FOLLOWPIN"
        case iowire = "IOWIRE"
        case corewire = "COREWIRE"
        case blockwire = "BLOCKWIRE"
        case blockagewire = "BLOCKAGEWIRE"
        case fillwire = "FILLWIRE"
        case drcfill = "DRCFILL"
    }

    public init(status: RouteStatus = .routed, layerName: String, width: Int32 = 0,
                points: [DEFRoutePoint] = [], shape: RouteShape? = nil) {
        self.status = status
        self.layerName = layerName
        self.width = width
        self.points = points
        self.shape = shape
    }

    /// Convenience init for backward compatibility with simple IRPoint arrays.
    public init(layerName: String, width: Int32 = 0, points: [IRPoint]) {
        self.status = .routed
        self.layerName = layerName
        self.width = width
        self.points = points.map { DEFRoutePoint(x: $0.x, y: $0.y) }
        self.shape = nil
    }
}

/// A point in a special net route, supporting wildcard (*) coordinates and via references.
public struct DEFRoutePoint: Hashable, Sendable, Codable {
    public var x: Int32?
    public var y: Int32?
    public var ext: Int32?
    public var viaName: String?

    public init(x: Int32? = nil, y: Int32? = nil, ext: Int32? = nil, viaName: String? = nil) {
        self.x = x
        self.y = y
        self.ext = ext
        self.viaName = viaName
    }

    /// Resolved point (nil → previous coordinate).
    public func resolved(previousX: Int32, previousY: Int32) -> IRPoint {
        IRPoint(x: x ?? previousX, y: y ?? previousY)
    }
}
