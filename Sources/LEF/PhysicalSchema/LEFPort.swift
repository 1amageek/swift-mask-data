public struct LEFPort: Hashable, Sendable, Codable {
    public var layerName: String
    public var rects: [LEFRect]
    public var polygons: [[LEFPoint]]
    public var paths: [LEFPath]
    public var vias: [LEFPortVia]
    public var portClass: PortClass?

    public enum PortClass: String, Hashable, Sendable, Codable {
        case none = "NONE"
        case core = "CORE"
        case bump = "BUMP"
    }

    public init(layerName: String, rects: [LEFRect], polygons: [[LEFPoint]] = [],
                vias: [LEFPortVia] = [], portClass: PortClass? = nil) {
        self.init(layerName: layerName, rects: rects, polygons: polygons, paths: [], vias: vias, portClass: portClass)
    }

    public init(layerName: String, rects: [LEFRect], polygons: [[LEFPoint]] = [], paths: [LEFPath],
                vias: [LEFPortVia] = [], portClass: PortClass? = nil) {
        self.layerName = layerName
        self.rects = rects
        self.polygons = polygons
        self.paths = paths
        self.vias = vias
        self.portClass = portClass
    }

    private enum CodingKeys: String, CodingKey {
        case layerName, rects, polygons, paths, vias, portClass
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layerName = try container.decode(String.self, forKey: .layerName)
        rects = try container.decode([LEFRect].self, forKey: .rects)
        polygons = try container.decode([[LEFPoint]].self, forKey: .polygons)
        paths = try container.decodeIfPresent([LEFPath].self, forKey: .paths) ?? []
        vias = try container.decode([LEFPortVia].self, forKey: .vias)
        portClass = try container.decodeIfPresent(PortClass.self, forKey: .portClass)
    }
}
