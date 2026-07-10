/// Root container for technology data in the intermediate representation.
///
/// `IRTechLibrary` is a format-agnostic, Codable representation of process
/// technology information. It can be populated from LEF, KLayout `.lyp`,
/// or JSON files and converted to a downstream `LayoutTechDatabase`.
public struct IRTechLibrary: Hashable, Sendable, Codable {
    public var name: String
    public var dbuPerMicron: Double
    public var layers: [IRTechLayerDef]
    public var vias: [IRTechViaDef]
    public var sites: [IRTechSiteDef]
    public var designRules: [IRTechDesignRule]
    public var enclosureRules: [IRTechEnclosureRule]
    public var extensionRules: [IRTechExtensionRule]
    public var minimumCutRules: [IRTechMinimumCutRule]
    public var antennaRules: [IRTechAntennaRule]
    public var metadata: [String: String]

    public init(
        name: String = "",
        dbuPerMicron: Double = 1000,
        layers: [IRTechLayerDef] = [],
        vias: [IRTechViaDef] = [],
        sites: [IRTechSiteDef] = [],
        designRules: [IRTechDesignRule] = [],
        enclosureRules: [IRTechEnclosureRule] = [],
        extensionRules: [IRTechExtensionRule] = [],
        minimumCutRules: [IRTechMinimumCutRule] = [],
        antennaRules: [IRTechAntennaRule] = [],
        metadata: [String: String] = [:]
    ) {
        self.name = name
        self.dbuPerMicron = dbuPerMicron
        self.layers = layers
        self.vias = vias
        self.sites = sites
        self.designRules = designRules
        self.enclosureRules = enclosureRules
        self.extensionRules = extensionRules
        self.minimumCutRules = minimumCutRules
        self.antennaRules = antennaRules
        self.metadata = metadata
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case dbuPerMicron
        case layers
        case vias
        case sites
        case designRules
        case enclosureRules
        case extensionRules
        case minimumCutRules
        case antennaRules
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.dbuPerMicron = try container.decode(Double.self, forKey: .dbuPerMicron)
        self.layers = try container.decode([IRTechLayerDef].self, forKey: .layers)
        self.vias = try container.decode([IRTechViaDef].self, forKey: .vias)
        self.sites = try container.decode([IRTechSiteDef].self, forKey: .sites)
        self.designRules = try container.decode([IRTechDesignRule].self, forKey: .designRules)
        self.enclosureRules = try container.decode([IRTechEnclosureRule].self, forKey: .enclosureRules)
        self.extensionRules = try container.decode([IRTechExtensionRule].self, forKey: .extensionRules)
        self.minimumCutRules = try container.decode([IRTechMinimumCutRule].self, forKey: .minimumCutRules)
        self.antennaRules = try container.decode([IRTechAntennaRule].self, forKey: .antennaRules)
        self.metadata = try container.decode([String: String].self, forKey: .metadata)
    }
}
