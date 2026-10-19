import TechIR

public struct LEFDocument: Hashable, Sendable, Codable {
    public var viaGenerationRules: [IRTechViaGenerationRule]
    public var propertyDefinitions: [IRTechPropertyDefinition]
    public var obstructionSpacingUsesMinimumWidth: Bool?
    public var hasDatabaseUnitsDeclaration: Bool
    public var unitDeclarations: IRTechUnitDeclarations
    public var version: String
    public var manufacturingGrid: Double?
    public var dbuPerMicron: Double
    public var layers: [LEFLayerDef]
    public var vias: [LEFViaDef]
    public var macros: [LEFMacroDef]
    public var sites: [LEFSiteDef]
    public var properties: [LEFProperty]
    public var busbitChars: String?
    public var dividerChar: String?

    public init(version: String = "5.8", dbuPerMicron: Double = 1000,
                layers: [LEFLayerDef] = [], vias: [LEFViaDef] = [], macros: [LEFMacroDef] = [],
                sites: [LEFSiteDef] = [], properties: [LEFProperty] = [],
                busbitChars: String? = nil, dividerChar: String? = nil, manufacturingGrid: Double? = nil, unitDeclarations: IRTechUnitDeclarations = .init(), hasDatabaseUnitsDeclaration: Bool = true, propertyDefinitions: [IRTechPropertyDefinition] = [], obstructionSpacingUsesMinimumWidth: Bool? = nil, viaGenerationRules: [IRTechViaGenerationRule] = []) {
        self.viaGenerationRules = viaGenerationRules
        self.propertyDefinitions = propertyDefinitions
        self.obstructionSpacingUsesMinimumWidth = obstructionSpacingUsesMinimumWidth
        self.hasDatabaseUnitsDeclaration = hasDatabaseUnitsDeclaration
        self.unitDeclarations = unitDeclarations
        self.manufacturingGrid = manufacturingGrid
        self.version = version
        self.dbuPerMicron = dbuPerMicron
        self.layers = layers
        self.vias = vias
        self.macros = macros
        self.sites = sites
        self.properties = properties
        self.busbitChars = busbitChars
        self.dividerChar = dividerChar
    }
    private enum CodingKeys: String, CodingKey {
        case viaGenerationRules
        case propertyDefinitions
        case obstructionSpacingUsesMinimumWidth
        case hasDatabaseUnitsDeclaration
        case version, manufacturingGrid, unitDeclarations, dbuPerMicron, layers, vias, macros, sites, properties, busbitChars, dividerChar
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        viaGenerationRules = try values.decodeIfPresent([IRTechViaGenerationRule].self, forKey: .viaGenerationRules) ?? []
        propertyDefinitions = try values.decodeIfPresent([IRTechPropertyDefinition].self, forKey: .propertyDefinitions) ?? []
        obstructionSpacingUsesMinimumWidth = try values.decodeIfPresent(Bool.self, forKey: .obstructionSpacingUsesMinimumWidth)
        hasDatabaseUnitsDeclaration = try values.decodeIfPresent(Bool.self, forKey: .hasDatabaseUnitsDeclaration) ?? true
        unitDeclarations = try values.decodeIfPresent(IRTechUnitDeclarations.self, forKey: .unitDeclarations) ?? .init()
        version = try values.decode(String.self, forKey: .version)
        manufacturingGrid = try values.decodeIfPresent(Double.self, forKey: .manufacturingGrid)
        dbuPerMicron = try values.decode(Double.self, forKey: .dbuPerMicron)
        layers = try values.decode([LEFLayerDef].self, forKey: .layers)
        vias = try values.decode([LEFViaDef].self, forKey: .vias)
        macros = try values.decode([LEFMacroDef].self, forKey: .macros)
        sites = try values.decode([LEFSiteDef].self, forKey: .sites)
        properties = try values.decode([LEFProperty].self, forKey: .properties)
        busbitChars = try values.decodeIfPresent(String.self, forKey: .busbitChars)
        dividerChar = try values.decodeIfPresent(String.self, forKey: .dividerChar)
    }

}
