public struct LEFSiteDef: Hashable, Sendable, Codable {
    public var name: String
    public var siteClass: SiteClass?
    public var symmetry: [LEFMacroDef.Symmetry]
    public var width: Double?
    public var height: Double?

    public enum SiteClass: String, Hashable, Sendable, Codable {
        case core = "CORE"
        case pad = "PAD"
    }

    public init(name: String, siteClass: SiteClass? = nil,
                symmetry: [LEFMacroDef.Symmetry] = [],
                width: Double? = nil, height: Double? = nil) {
        self.name = name
        self.siteClass = siteClass
        self.symmetry = symmetry
        self.width = width
        self.height = height
    }
}
