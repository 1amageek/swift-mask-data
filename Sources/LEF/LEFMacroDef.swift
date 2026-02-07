public struct LEFMacroDef: Hashable, Sendable, Codable {
    public var name: String
    public var macroClass: MacroClass?
    public var subClass: String?
    public var width: Double?
    public var height: Double?
    public var symmetry: [Symmetry]
    public var pins: [LEFPinDef]
    public var obs: [LEFPort]
    public var origin: LEFPoint?
    public var foreign: LEFForeign?
    public var site: String?
    public var fixedMask: Bool
    public var properties: [LEFProperty]
    public var eeq: String?
    public var source: String?

    public enum MacroClass: String, Hashable, Sendable, Codable {
        case core = "CORE"
        case pad = "PAD"
        case block = "BLOCK"
        case ring = "RING"
        case endcap = "ENDCAP"
        case cover = "COVER"
    }

    public enum Symmetry: String, Hashable, Sendable, Codable {
        case x = "X"
        case y = "Y"
        case r90 = "R90"
    }

    public init(name: String, macroClass: MacroClass? = nil, subClass: String? = nil,
                width: Double? = nil, height: Double? = nil,
                symmetry: [Symmetry] = [], pins: [LEFPinDef] = [], obs: [LEFPort] = [],
                origin: LEFPoint? = nil, foreign: LEFForeign? = nil,
                site: String? = nil, fixedMask: Bool = false,
                properties: [LEFProperty] = [], eeq: String? = nil, source: String? = nil) {
        self.name = name
        self.macroClass = macroClass
        self.subClass = subClass
        self.width = width
        self.height = height
        self.symmetry = symmetry
        self.pins = pins
        self.obs = obs
        self.origin = origin
        self.foreign = foreign
        self.site = site
        self.fixedMask = fixedMask
        self.properties = properties
        self.eeq = eeq
        self.source = source
    }
}

public struct LEFForeign: Hashable, Sendable, Codable {
    public var cellName: String
    public var point: LEFPoint?

    public init(cellName: String, point: LEFPoint? = nil) {
        self.cellName = cellName
        self.point = point
    }
}
