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
        self.antennaRules = antennaRules
        self.metadata = metadata
    }
}
