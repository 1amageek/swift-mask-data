/// Technology layer definition in the intermediate representation.
public struct IRTechLayerDef: Hashable, Sendable, Codable {
    public var enclosures: [IRTechLayerEnclosure]
    public var currentDensityLimits: [IRTechCurrentDensityLimit]
    public var antennaStatements: [IRTechAntennaStatement]
    public var properties: [IRTechPropertyAssignment]
    public var subtype: IRTechLayerSubtype?
    public var name: String
    public var type: IRTechLayerType
    public var gdsLayer: Int?
    public var gdsDatatype: Int?
    public var direction: IRTechLayerDirection?
    public var pitch: IRTechAxisValue?
    public var offset: IRTechAxisValue?
    public var width: Double?
    public var spacing: Double?
    /// Routing sheet resistance in ohms per square.
    public var resistance: Double?
    /// Resistance of one cut in ohms, independent of total-via resistance.
    public var cutResistanceOhms: Double?
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
        pitch: IRTechAxisValue? = nil,
        offset: IRTechAxisValue? = nil,
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
        maxDensity: Double? = nil,
        properties: [IRTechPropertyAssignment] = [],
        subtype: IRTechLayerSubtype? = nil,
        antennaStatements: [IRTechAntennaStatement] = [],
        enclosures: [IRTechLayerEnclosure] = [],
        cutResistanceOhms: Double? = nil,
        currentDensityLimits: [IRTechCurrentDensityLimit] = []
    ) {
        self.enclosures = enclosures
        self.currentDensityLimits = currentDensityLimits
        self.antennaStatements = antennaStatements
        self.properties = properties
        self.subtype = subtype
        self.name = name
        self.type = type
        self.gdsLayer = gdsLayer
        self.gdsDatatype = gdsDatatype
        self.direction = direction
        self.pitch = pitch
        self.offset = offset
        self.width = width
        self.spacing = spacing
        self.resistance = resistance
        self.cutResistanceOhms = cutResistanceOhms
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
    private enum CodingKeys: String, CodingKey {
        case enclosures, antennaStatements, currentDensityLimits, properties, subtype, name, type, gdsLayer, gdsDatatype, direction, pitch, offset, width, spacing, resistance, cutResistanceOhms, capacitance, thickness, color, fillPattern, visibleByDefault, spacingTable, minArea, minDensity, maxDensity
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enclosures = try values.decodeIfPresent([IRTechLayerEnclosure].self, forKey: .enclosures) ?? []
        currentDensityLimits = try values.decodeIfPresent([IRTechCurrentDensityLimit].self, forKey: .currentDensityLimits) ?? []
        antennaStatements = try values.decodeIfPresent([IRTechAntennaStatement].self, forKey: .antennaStatements) ?? []
        properties = try values.decodeIfPresent([IRTechPropertyAssignment].self, forKey: .properties) ?? []
        subtype = try values.decodeIfPresent(IRTechLayerSubtype.self, forKey: .subtype)
        name = try values.decode(String.self, forKey: .name)
        type = try values.decode(IRTechLayerType.self, forKey: .type)
        gdsLayer = try values.decodeIfPresent(Int.self, forKey: .gdsLayer)
        gdsDatatype = try values.decodeIfPresent(Int.self, forKey: .gdsDatatype)
        direction = try values.decodeIfPresent(IRTechLayerDirection.self, forKey: .direction)
        pitch = try values.decodeIfPresent(IRTechAxisValue.self, forKey: .pitch)
        offset = try values.decodeIfPresent(IRTechAxisValue.self, forKey: .offset)
        width = try values.decodeIfPresent(Double.self, forKey: .width)
        spacing = try values.decodeIfPresent(Double.self, forKey: .spacing)
        resistance = try values.decodeIfPresent(Double.self, forKey: .resistance)
        cutResistanceOhms = try values.decodeIfPresent(Double.self, forKey: .cutResistanceOhms)
        capacitance = try values.decodeIfPresent(Double.self, forKey: .capacitance)
        thickness = try values.decodeIfPresent(Double.self, forKey: .thickness)
        color = try values.decodeIfPresent(IRTechColor.self, forKey: .color)
        fillPattern = try values.decodeIfPresent(IRTechFillPattern.self, forKey: .fillPattern)
        visibleByDefault = try values.decodeIfPresent(Bool.self, forKey: .visibleByDefault)
        spacingTable = try values.decodeIfPresent(IRTechSpacingTable.self, forKey: .spacingTable)
        minArea = try values.decodeIfPresent(Double.self, forKey: .minArea)
        minDensity = try values.decodeIfPresent(Double.self, forKey: .minDensity)
        maxDensity = try values.decodeIfPresent(Double.self, forKey: .maxDensity)
    }

}
