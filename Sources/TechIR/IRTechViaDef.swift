/// Via definition in the intermediate representation.
public struct IRTechViaDef: Hashable, Sendable, Codable {
    public var name: String
    public var cutLayerName: String
    public var topLayerName: String
    public var bottomLayerName: String
    public var cutWidth: Double?
    public var cutHeight: Double?
    public var enclosure: IRTechEnclosureValues?
    public var spacing: Double?
    public var resistance: Double?
    public var layers: [IRTechViaLayerGeometry]

    public init(
        name: String,
        cutLayerName: String,
        topLayerName: String,
        bottomLayerName: String,
        cutWidth: Double? = nil,
        cutHeight: Double? = nil,
        enclosure: IRTechEnclosureValues? = nil,
        spacing: Double? = nil,
        resistance: Double? = nil,
        layers: [IRTechViaLayerGeometry] = []
    ) {
        self.name = name
        self.cutLayerName = cutLayerName
        self.topLayerName = topLayerName
        self.bottomLayerName = bottomLayerName
        self.cutWidth = cutWidth
        self.cutHeight = cutHeight
        self.enclosure = enclosure
        self.spacing = spacing
        self.resistance = resistance
        self.layers = layers
    }
}

/// Geometry for a single layer within a via definition.
public struct IRTechViaLayerGeometry: Hashable, Sendable, Codable {
    public var layerName: String
    public var rects: [IRTechRect]

    public init(layerName: String, rects: [IRTechRect] = []) {
        self.layerName = layerName
        self.rects = rects
    }
}
