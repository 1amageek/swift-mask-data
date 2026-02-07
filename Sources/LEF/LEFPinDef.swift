public struct LEFPinDef: Hashable, Sendable, Codable {
    public var name: String
    public var direction: PinDirection?
    public var use: PinUse?
    public var shape: PinShape?
    public var ports: [LEFPort]
    public var antennaDiffArea: Double?
    public var antennaGateArea: Double?
    public var antennaModel: String?
    public var taperrule: String?
    public var properties: [LEFProperty]

    public enum PinDirection: String, Hashable, Sendable, Codable {
        case input = "INPUT"
        case output = "OUTPUT"
        case inout_ = "INOUT"
        case feedthru = "FEEDTHRU"
    }

    public enum PinUse: String, Hashable, Sendable, Codable {
        case signal = "SIGNAL"
        case power = "POWER"
        case ground = "GROUND"
        case clock = "CLOCK"
        case analog = "ANALOG"
    }

    public enum PinShape: String, Hashable, Sendable, Codable {
        case abutment = "ABUTMENT"
        case ring = "RING"
        case feedthru = "FEEDTHRU"
    }

    public init(name: String, direction: PinDirection? = nil, use: PinUse? = nil,
                shape: PinShape? = nil, ports: [LEFPort] = [],
                antennaDiffArea: Double? = nil, antennaGateArea: Double? = nil,
                antennaModel: String? = nil, taperrule: String? = nil,
                properties: [LEFProperty] = []) {
        self.name = name
        self.direction = direction
        self.use = use
        self.shape = shape
        self.ports = ports
        self.antennaDiffArea = antennaDiffArea
        self.antennaGateArea = antennaGateArea
        self.antennaModel = antennaModel
        self.taperrule = taperrule
        self.properties = properties
    }
}

public struct LEFPort: Hashable, Sendable, Codable {
    public var layerName: String
    public var rects: [LEFRect]
    public var polygons: [[LEFPoint]]
    public var vias: [LEFPortVia]
    public var portClass: PortClass?

    public enum PortClass: String, Hashable, Sendable, Codable {
        case none = "NONE"
        case core = "CORE"
        case bump = "BUMP"
    }

    public init(layerName: String, rects: [LEFRect], polygons: [[LEFPoint]] = [],
                vias: [LEFPortVia] = [], portClass: PortClass? = nil) {
        self.layerName = layerName
        self.rects = rects
        self.polygons = polygons
        self.vias = vias
        self.portClass = portClass
    }
}

public struct LEFPortVia: Hashable, Sendable, Codable {
    public var viaName: String
    public var point: LEFPoint

    public init(viaName: String, point: LEFPoint) {
        self.viaName = viaName
        self.point = point
    }
}
