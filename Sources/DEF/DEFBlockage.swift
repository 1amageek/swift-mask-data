import LayoutIR

/// Represents a BLOCKAGES entry in DEF.
public struct DEFBlockage: Hashable, Sendable, Codable {
    public var blockageType: BlockageType
    public var layerName: String?
    public var component: String?
    public var pushdown: Bool
    public var rects: [DEFRect]
    public var polygons: [[IRPoint]]

    public enum BlockageType: String, Hashable, Sendable, Codable {
        case placement = "PLACEMENT"
        case routing = "ROUTING"
    }

    public init(blockageType: BlockageType, layerName: String? = nil,
                component: String? = nil, pushdown: Bool = false,
                rects: [DEFRect] = [], polygons: [[IRPoint]] = []) {
        self.blockageType = blockageType
        self.layerName = layerName
        self.component = component
        self.pushdown = pushdown
        self.rects = rects
        self.polygons = polygons
    }
}

/// A rectangle in DEF coordinates.
public struct DEFRect: Hashable, Sendable, Codable {
    public var x1: Int32
    public var y1: Int32
    public var x2: Int32
    public var y2: Int32

    public init(x1: Int32, y1: Int32, x2: Int32, y2: Int32) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }
}
