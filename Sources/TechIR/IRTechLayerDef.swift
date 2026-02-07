/// Technology layer definition in the intermediate representation.
public struct IRTechLayerDef: Hashable, Sendable, Codable {
    public var name: String
    public var type: IRTechLayerType
    public var gdsLayer: Int?
    public var gdsDatatype: Int?
    public var direction: IRTechLayerDirection?
    public var pitch: Double?
    public var width: Double?
    public var spacing: Double?
    public var resistance: Double?
    public var capacitance: Double?
    public var thickness: Double?
    public var color: IRTechColor?
    public var fillPattern: IRTechFillPattern?
    public var visibleByDefault: Bool?
    public var spacingTable: IRTechSpacingTable?
    public var minArea: Double?
    public var minDensity: Double?
    public var maxDensity: Double?

    public init(
        name: String,
        type: IRTechLayerType,
        gdsLayer: Int? = nil,
        gdsDatatype: Int? = nil,
        direction: IRTechLayerDirection? = nil,
        pitch: Double? = nil,
        width: Double? = nil,
        spacing: Double? = nil,
        resistance: Double? = nil,
        capacitance: Double? = nil,
        thickness: Double? = nil,
        color: IRTechColor? = nil,
        fillPattern: IRTechFillPattern? = nil,
        visibleByDefault: Bool? = nil,
        spacingTable: IRTechSpacingTable? = nil,
        minArea: Double? = nil,
        minDensity: Double? = nil,
        maxDensity: Double? = nil
    ) {
        self.name = name
        self.type = type
        self.gdsLayer = gdsLayer
        self.gdsDatatype = gdsDatatype
        self.direction = direction
        self.pitch = pitch
        self.width = width
        self.spacing = spacing
        self.resistance = resistance
        self.capacitance = capacitance
        self.thickness = thickness
        self.color = color
        self.fillPattern = fillPattern
        self.visibleByDefault = visibleByDefault
        self.spacingTable = spacingTable
        self.minArea = minArea
        self.minDensity = minDensity
        self.maxDensity = maxDensity
    }
}
