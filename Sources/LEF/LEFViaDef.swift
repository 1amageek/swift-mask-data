public struct LEFViaDef: Hashable, Sendable, Codable {
    public var name: String
    public var layers: [LEFViaLayer]
    public var isDefault: Bool
    public var isGenerate: Bool
    public var viaRule: String?
    public var cutSize: (Double, Double)?
    public var cutSpacing: (Double, Double)?
    public var enclosure: (Double, Double, Double, Double)?
    public var rowCol: (Int, Int)?
    public var resistance: Double?

    public struct LEFViaLayer: Hashable, Sendable, Codable {
        public var layerName: String
        public var rects: [LEFRect]
        public var polygons: [[LEFPoint]]

        public init(layerName: String, rects: [LEFRect], polygons: [[LEFPoint]] = []) {
            self.layerName = layerName
            self.rects = rects
            self.polygons = polygons
        }
    }

    public init(name: String, layers: [LEFViaLayer], isDefault: Bool = false,
                isGenerate: Bool = false, viaRule: String? = nil,
                cutSize: (Double, Double)? = nil, cutSpacing: (Double, Double)? = nil,
                enclosure: (Double, Double, Double, Double)? = nil,
                rowCol: (Int, Int)? = nil, resistance: Double? = nil) {
        self.name = name
        self.layers = layers
        self.isDefault = isDefault
        self.isGenerate = isGenerate
        self.viaRule = viaRule
        self.cutSize = cutSize
        self.cutSpacing = cutSpacing
        self.enclosure = enclosure
        self.rowCol = rowCol
        self.resistance = resistance
    }

    // Manual Hashable/Equatable/Codable for tuples
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(layers)
        hasher.combine(isDefault)
        hasher.combine(isGenerate)
        hasher.combine(viaRule)
        hasher.combine(resistance)
        if let cs = cutSize { hasher.combine(cs.0); hasher.combine(cs.1) }
        if let csp = cutSpacing { hasher.combine(csp.0); hasher.combine(csp.1) }
        if let e = enclosure { hasher.combine(e.0); hasher.combine(e.1); hasher.combine(e.2); hasher.combine(e.3) }
        if let rc = rowCol { hasher.combine(rc.0); hasher.combine(rc.1) }
    }

    public static func == (lhs: LEFViaDef, rhs: LEFViaDef) -> Bool {
        guard lhs.name == rhs.name, lhs.layers == rhs.layers,
              lhs.isDefault == rhs.isDefault, lhs.isGenerate == rhs.isGenerate,
              lhs.viaRule == rhs.viaRule, lhs.resistance == rhs.resistance else { return false }
        if lhs.cutSize?.0 != rhs.cutSize?.0 || lhs.cutSize?.1 != rhs.cutSize?.1 { return false }
        if lhs.cutSpacing?.0 != rhs.cutSpacing?.0 || lhs.cutSpacing?.1 != rhs.cutSpacing?.1 { return false }
        if lhs.enclosure?.0 != rhs.enclosure?.0 || lhs.enclosure?.1 != rhs.enclosure?.1 ||
           lhs.enclosure?.2 != rhs.enclosure?.2 || lhs.enclosure?.3 != rhs.enclosure?.3 { return false }
        if lhs.rowCol?.0 != rhs.rowCol?.0 || lhs.rowCol?.1 != rhs.rowCol?.1 { return false }
        return true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(layers, forKey: .layers)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(isGenerate, forKey: .isGenerate)
        try container.encodeIfPresent(viaRule, forKey: .viaRule)
        try container.encodeIfPresent(resistance, forKey: .resistance)
        if let cs = cutSize {
            try container.encode([cs.0, cs.1], forKey: .cutSize)
        }
        if let csp = cutSpacing {
            try container.encode([csp.0, csp.1], forKey: .cutSpacing)
        }
        if let e = enclosure {
            try container.encode([e.0, e.1, e.2, e.3], forKey: .enclosure)
        }
        if let rc = rowCol {
            try container.encode([rc.0, rc.1], forKey: .rowCol)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        layers = try container.decode([LEFViaLayer].self, forKey: .layers)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        isGenerate = try container.decodeIfPresent(Bool.self, forKey: .isGenerate) ?? false
        viaRule = try container.decodeIfPresent(String.self, forKey: .viaRule)
        resistance = try container.decodeIfPresent(Double.self, forKey: .resistance)
        if let arr = try container.decodeIfPresent([Double].self, forKey: .cutSize), arr.count == 2 {
            cutSize = (arr[0], arr[1])
        } else { cutSize = nil }
        if let arr = try container.decodeIfPresent([Double].self, forKey: .cutSpacing), arr.count == 2 {
            cutSpacing = (arr[0], arr[1])
        } else { cutSpacing = nil }
        if let arr = try container.decodeIfPresent([Double].self, forKey: .enclosure), arr.count == 4 {
            enclosure = (arr[0], arr[1], arr[2], arr[3])
        } else { enclosure = nil }
        if let arr = try container.decodeIfPresent([Int].self, forKey: .rowCol), arr.count == 2 {
            rowCol = (arr[0], arr[1])
        } else { rowCol = nil }
    }

    private enum CodingKeys: String, CodingKey {
        case name, layers, isDefault, isGenerate, viaRule, resistance
        case cutSize, cutSpacing, enclosure, rowCol
    }
}

public struct LEFRect: Hashable, Sendable, Codable {
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double
    public var mask: Int?

    public init(x1: Double, y1: Double, x2: Double, y2: Double, mask: Int? = nil) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
        self.mask = mask
    }
}

public struct LEFPoint: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
