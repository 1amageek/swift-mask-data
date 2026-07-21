public struct LEFLayerDef: Hashable, Sendable, Codable {
    public var name: String
    public var type: LayerType
    public var direction: Direction?
    public var pitch: Double?
    public var width: Double?
    public var spacing: Double?
    public var offset: Double?
    public var resistance: Double?
    public var capacitance: Double?
    public var edgeCapacitance: Double?
    public var thickness: Double?
    public var minwidth: Double?
    public var maxwidth: Double?
    public var area: Double?
    public var enclosure: LEFEnclosure?
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
                pitch: Double? = nil, width: Double? = nil, spacing: Double? = nil,
                offset: Double? = nil, resistance: Double? = nil,
                capacitance: Double? = nil, edgeCapacitance: Double? = nil,
                thickness: Double? = nil, minwidth: Double? = nil,
                maxwidth: Double? = nil, area: Double? = nil,
                enclosure: LEFEnclosure? = nil, spacingTable: LEFSpacingTable? = nil,
                minimumDensity: Double? = nil, maximumDensity: Double? = nil,
                densityCheckWindow: DensityCheckWindow? = nil,
                densityCheckStep: Double? = nil) {
        self.name = name
        self.type = type
        self.direction = direction
        self.pitch = pitch
        self.width = width
        self.spacing = spacing
        self.offset = offset
        self.resistance = resistance
        self.capacitance = capacitance
        self.edgeCapacitance = edgeCapacitance
        self.thickness = thickness
        self.minwidth = minwidth
        self.maxwidth = maxwidth
        self.area = area
        self.enclosure = enclosure
        self.spacingTable = spacingTable
        self.minimumDensity = minimumDensity
        self.maximumDensity = maximumDensity
        self.densityCheckWindow = densityCheckWindow
        self.densityCheckStep = densityCheckStep
    }
}

public struct LEFEnclosure: Hashable, Sendable, Codable {
    public var overhang1: Double
    public var overhang2: Double

    public init(overhang1: Double, overhang2: Double) {
        self.overhang1 = overhang1
        self.overhang2 = overhang2
    }
}

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
