import LayoutIR

/// A key-value property in DEF.
public struct DEFProperty: Hashable, Sendable, Codable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// A PROPERTYDEFINITIONS entry in DEF.
public struct DEFPropertyDefinition: Hashable, Sendable, Codable {
    public var objectType: String
    public var propName: String
    public var propType: String
    public var defaultValue: String?

    public init(objectType: String, propName: String, propType: String,
                defaultValue: String? = nil) {
        self.objectType = objectType
        self.propName = propName
        self.propType = propType
        self.defaultValue = defaultValue
    }
}

/// A VIAS definition entry in DEF.
public struct DEFViaDef: Hashable, Sendable, Codable {
    public var name: String
    public var layers: [DEFViaLayer]
    public var viaRule: String?
    public var cutSize: (width: Int32, height: Int32)?
    public var cutSpacing: (x: Int32, y: Int32)?
    public var botEnclosure: (x: Int32, y: Int32)?
    public var topEnclosure: (x: Int32, y: Int32)?
    public var rowCol: (rows: Int32, cols: Int32)?

    public init(name: String, layers: [DEFViaLayer] = [], viaRule: String? = nil,
                cutSize: (width: Int32, height: Int32)? = nil,
                cutSpacing: (x: Int32, y: Int32)? = nil,
                botEnclosure: (x: Int32, y: Int32)? = nil,
                topEnclosure: (x: Int32, y: Int32)? = nil,
                rowCol: (rows: Int32, cols: Int32)? = nil) {
        self.name = name
        self.layers = layers
        self.viaRule = viaRule
        self.cutSize = cutSize
        self.cutSpacing = cutSpacing
        self.botEnclosure = botEnclosure
        self.topEnclosure = topEnclosure
        self.rowCol = rowCol
    }

    // Manual Hashable/Equatable for tuples
    public static func == (lhs: DEFViaDef, rhs: DEFViaDef) -> Bool {
        lhs.name == rhs.name && lhs.layers == rhs.layers &&
        lhs.viaRule == rhs.viaRule &&
        lhs.cutSize?.width == rhs.cutSize?.width && lhs.cutSize?.height == rhs.cutSize?.height &&
        lhs.cutSpacing?.x == rhs.cutSpacing?.x && lhs.cutSpacing?.y == rhs.cutSpacing?.y &&
        lhs.botEnclosure?.x == rhs.botEnclosure?.x && lhs.botEnclosure?.y == rhs.botEnclosure?.y &&
        lhs.topEnclosure?.x == rhs.topEnclosure?.x && lhs.topEnclosure?.y == rhs.topEnclosure?.y &&
        lhs.rowCol?.rows == rhs.rowCol?.rows && lhs.rowCol?.cols == rhs.rowCol?.cols
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(layers)
        hasher.combine(viaRule)
        hasher.combine(cutSize?.width); hasher.combine(cutSize?.height)
        hasher.combine(cutSpacing?.x); hasher.combine(cutSpacing?.y)
        hasher.combine(botEnclosure?.x); hasher.combine(botEnclosure?.y)
        hasher.combine(topEnclosure?.x); hasher.combine(topEnclosure?.y)
        hasher.combine(rowCol?.rows); hasher.combine(rowCol?.cols)
    }

    enum CodingKeys: String, CodingKey {
        case name, layers, viaRule
        case cutSizeW, cutSizeH, cutSpacingX, cutSpacingY
        case botEncX, botEncY, topEncX, topEncY
        case rowColRows, rowColCols
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        layers = try c.decode([DEFViaLayer].self, forKey: .layers)
        viaRule = try c.decodeIfPresent(String.self, forKey: .viaRule)
        if let w = try c.decodeIfPresent(Int32.self, forKey: .cutSizeW),
           let h = try c.decodeIfPresent(Int32.self, forKey: .cutSizeH) {
            cutSize = (w, h)
        } else { cutSize = nil }
        if let x = try c.decodeIfPresent(Int32.self, forKey: .cutSpacingX),
           let y = try c.decodeIfPresent(Int32.self, forKey: .cutSpacingY) {
            cutSpacing = (x, y)
        } else { cutSpacing = nil }
        if let x = try c.decodeIfPresent(Int32.self, forKey: .botEncX),
           let y = try c.decodeIfPresent(Int32.self, forKey: .botEncY) {
            botEnclosure = (x, y)
        } else { botEnclosure = nil }
        if let x = try c.decodeIfPresent(Int32.self, forKey: .topEncX),
           let y = try c.decodeIfPresent(Int32.self, forKey: .topEncY) {
            topEnclosure = (x, y)
        } else { topEnclosure = nil }
        if let r = try c.decodeIfPresent(Int32.self, forKey: .rowColRows),
           let co = try c.decodeIfPresent(Int32.self, forKey: .rowColCols) {
            rowCol = (r, co)
        } else { rowCol = nil }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(layers, forKey: .layers)
        try c.encodeIfPresent(viaRule, forKey: .viaRule)
        try c.encodeIfPresent(cutSize?.width, forKey: .cutSizeW)
        try c.encodeIfPresent(cutSize?.height, forKey: .cutSizeH)
        try c.encodeIfPresent(cutSpacing?.x, forKey: .cutSpacingX)
        try c.encodeIfPresent(cutSpacing?.y, forKey: .cutSpacingY)
        try c.encodeIfPresent(botEnclosure?.x, forKey: .botEncX)
        try c.encodeIfPresent(botEnclosure?.y, forKey: .botEncY)
        try c.encodeIfPresent(topEnclosure?.x, forKey: .topEncX)
        try c.encodeIfPresent(topEnclosure?.y, forKey: .topEncY)
        try c.encodeIfPresent(rowCol?.rows, forKey: .rowColRows)
        try c.encodeIfPresent(rowCol?.cols, forKey: .rowColCols)
    }
}

/// A via layer definition within a DEFViaDef.
public struct DEFViaLayer: Hashable, Sendable, Codable {
    public var layerName: String
    public var rects: [DEFRect]

    public init(layerName: String, rects: [DEFRect] = []) {
        self.layerName = layerName
        self.rects = rects
    }
}

/// A FILLS entry in DEF.
public struct DEFFill: Hashable, Sendable, Codable {
    public var layerName: String
    public var rects: [DEFRect]
    public var polygons: [[IRPoint]]
    public var opc: Bool

    public init(layerName: String, rects: [DEFRect] = [],
                polygons: [[IRPoint]] = [], opc: Bool = false) {
        self.layerName = layerName
        self.rects = rects
        self.polygons = polygons
        self.opc = opc
    }
}

/// A GROUPS entry in DEF.
public struct DEFGroup: Hashable, Sendable, Codable {
    public var name: String
    public var components: [String]
    public var region: String?
    public var properties: [DEFProperty]

    public init(name: String, components: [String] = [],
                region: String? = nil, properties: [DEFProperty] = []) {
        self.name = name
        self.components = components
        self.region = region
        self.properties = properties
    }
}
