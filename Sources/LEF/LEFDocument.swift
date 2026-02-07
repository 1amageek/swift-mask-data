public struct LEFDocument: Hashable, Sendable, Codable {
    public var version: String
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
                busbitChars: String? = nil, dividerChar: String? = nil) {
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
}
