import TechIR

public struct LEFLayerDef: Hashable, Sendable, Codable {
    public var currentDensityLimits: [IRTechCurrentDensityLimit]
    public var antennaStatements: [IRTechAntennaStatement]
    public var properties: [IRTechPropertyAssignment]
    public var subtype: IRTechLayerSubtype?
    public var name: String
    public var type: LayerType
    public var direction: Direction?
    public var pitch: IRTechAxisValue?
    public var width: Double?
    public var spacing: Double?
    public var offset: IRTechAxisValue?
    /// Routing sheet resistance in ohms per square.
    public var resistance: Double?
    /// Resistance of one cut in ohms, independent of total-via resistance.
    public var cutResistanceOhms: Double?
    public var capacitance: Double?
    public var edgeCapacitance: Double?
    public var thickness: Double?
    public var minwidth: Double?
    public var maxwidth: Double?
    public var area: Double?
    /// Raw unconditional minimum hole areas in square microns; supported source has at most one.
    public var minimumEnclosedAreas: [Double]
    public var enclosures: [IRTechLayerEnclosure]

    /// Legacy view for one unqualified rule; directional and alternative rules require enclosures.
    public var enclosure: LEFEnclosure? {
        get { enclosures.count == 1 && enclosures[0].side == nil ? enclosures[0] : nil }
        set {
            enclosures.removeAll { $0.side == nil }
            if let newValue { enclosures.insert(newValue, at: 0) }
        }
    }
    public var spacingTable: LEFSpacingTable?
    public var minimumDensity: Double?
    public var maximumDensity: Double?
    public var densityCheckWindow: DensityCheckWindow?
    public var densityCheckStep: Double?

    public struct DensityCheckWindow: Hashable, Sendable, Codable {
        public var length: Double
        public var width: Double

        public init(length: Double, width: Double) {
            self.length = length
            self.width = width
        }
    }

    public enum LayerType: String, Hashable, Sendable, Codable {
        case routing = "ROUTING"
        case cut = "CUT"
        case masterslice = "MASTERSLICE"
        case overlap = "OVERLAP"
        case implant = "IMPLANT"
    }

    public enum Direction: String, Hashable, Sendable, Codable {
        case horizontal = "HORIZONTAL"
        case vertical = "VERTICAL"
    }

    public init(name: String, type: LayerType, direction: Direction? = nil,
                pitch: IRTechAxisValue? = nil, width: Double? = nil, spacing: Double? = nil,
                offset: IRTechAxisValue? = nil, resistance: Double? = nil,
                capacitance: Double? = nil, edgeCapacitance: Double? = nil,
                thickness: Double? = nil, minwidth: Double? = nil,
                maxwidth: Double? = nil, area: Double? = nil,
                enclosure: LEFEnclosure? = nil, spacingTable: LEFSpacingTable? = nil,
                minimumDensity: Double? = nil, maximumDensity: Double? = nil,
                densityCheckWindow: DensityCheckWindow? = nil,
                densityCheckStep: Double? = nil,
                properties: [IRTechPropertyAssignment] = [], subtype: IRTechLayerSubtype? = nil,
                antennaStatements: [IRTechAntennaStatement] = [],
                enclosures: [IRTechLayerEnclosure] = [],
                cutResistanceOhms: Double? = nil,
                currentDensityLimits: [IRTechCurrentDensityLimit] = [],
                minimumEnclosedAreas: [Double] = []) {
        self.minimumEnclosedAreas = minimumEnclosedAreas
        self.currentDensityLimits = currentDensityLimits
        self.antennaStatements = antennaStatements
        self.properties = properties
        self.subtype = subtype
        self.name = name
        self.type = type
        self.direction = direction
        self.pitch = pitch
        self.width = width
        self.spacing = spacing
        self.offset = offset
        self.resistance = resistance
        self.cutResistanceOhms = cutResistanceOhms
        self.capacitance = capacitance
        self.edgeCapacitance = edgeCapacitance
        self.thickness = thickness
        self.minwidth = minwidth
        self.maxwidth = maxwidth
        self.area = area
        self.enclosures = enclosure.map { [$0] } ?? []
        self.enclosures.append(contentsOf: enclosures)
        self.spacingTable = spacingTable
        self.minimumDensity = minimumDensity
        self.maximumDensity = maximumDensity
        self.densityCheckWindow = densityCheckWindow
        self.densityCheckStep = densityCheckStep
    }
    private enum LegacyCodingKeys: String, CodingKey { case enclosure }

    private enum CodingKeys: String, CodingKey {
        case minimumEnclosedAreas, antennaStatements, currentDensityLimits, properties, subtype, name, type, direction, pitch, width, spacing, offset, resistance, cutResistanceOhms, capacitance, edgeCapacitance, thickness, minwidth, maxwidth, area, enclosures, spacingTable, minimumDensity, maximumDensity, densityCheckWindow, densityCheckStep
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        minimumEnclosedAreas = try values.decodeIfPresent([Double].self, forKey: .minimumEnclosedAreas) ?? []
        currentDensityLimits = try values.decodeIfPresent([IRTechCurrentDensityLimit].self, forKey: .currentDensityLimits) ?? []
        antennaStatements = try values.decodeIfPresent([IRTechAntennaStatement].self, forKey: .antennaStatements) ?? []
        properties = try values.decodeIfPresent([IRTechPropertyAssignment].self, forKey: .properties) ?? []
        subtype = try values.decodeIfPresent(IRTechLayerSubtype.self, forKey: .subtype)
        name = try values.decode(String.self, forKey: .name)
        type = try values.decode(LayerType.self, forKey: .type)
        direction = try values.decodeIfPresent(Direction.self, forKey: .direction)
        pitch = try values.decodeIfPresent(IRTechAxisValue.self, forKey: .pitch)
        width = try values.decodeIfPresent(Double.self, forKey: .width)
        spacing = try values.decodeIfPresent(Double.self, forKey: .spacing)
        offset = try values.decodeIfPresent(IRTechAxisValue.self, forKey: .offset)
        resistance = try values.decodeIfPresent(Double.self, forKey: .resistance)
        cutResistanceOhms = try values.decodeIfPresent(Double.self, forKey: .cutResistanceOhms)
        capacitance = try values.decodeIfPresent(Double.self, forKey: .capacitance)
        edgeCapacitance = try values.decodeIfPresent(Double.self, forKey: .edgeCapacitance)
        thickness = try values.decodeIfPresent(Double.self, forKey: .thickness)
        minwidth = try values.decodeIfPresent(Double.self, forKey: .minwidth)
        maxwidth = try values.decodeIfPresent(Double.self, forKey: .maxwidth)
        area = try values.decodeIfPresent(Double.self, forKey: .area)
        let retained = try values.decodeIfPresent([IRTechLayerEnclosure].self, forKey: .enclosures)
        let legacyValues = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let legacy = try legacyValues.decodeIfPresent(LEFEnclosure.self, forKey: .enclosure)
        if let retained {
            if let legacy, retained != [legacy] {
                throw DecodingError.dataCorruptedError(forKey: .enclosures, in: values,
                    debugDescription: "Legacy enclosure disagrees with exact enclosure array")
            }
            enclosures = retained
        } else { enclosures = legacy.map { [$0] } ?? [] }
        spacingTable = try values.decodeIfPresent(LEFSpacingTable.self, forKey: .spacingTable)
        minimumDensity = try values.decodeIfPresent(Double.self, forKey: .minimumDensity)
        maximumDensity = try values.decodeIfPresent(Double.self, forKey: .maximumDensity)
        densityCheckWindow = try values.decodeIfPresent(DensityCheckWindow.self, forKey: .densityCheckWindow)
        densityCheckStep = try values.decodeIfPresent(Double.self, forKey: .densityCheckStep)
    }

}

public typealias LEFEnclosure = IRTechLayerEnclosure

public struct LEFSpacingTable: Hashable, Sendable, Codable {
    public var parallelRunLengths: [Double]
    public var widthEntries: [WidthEntry]

    public struct WidthEntry: Hashable, Sendable, Codable {
        public var width: Double
        public var spacings: [Double]

        public init(width: Double, spacings: [Double]) {
            self.width = width
            self.spacings = spacings
        }
    }

    public init(parallelRunLengths: [Double], widthEntries: [WidthEntry]) {
        self.parallelRunLengths = parallelRunLengths
        self.widthEntries = widthEntries
    }
}
