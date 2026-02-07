/// Placement site definition in the intermediate representation.
public struct IRTechSiteDef: Hashable, Sendable, Codable {
    public var name: String
    public var siteClass: IRTechSiteClass?
    public var width: Double?
    public var height: Double?
    public var symmetry: [IRTechSymmetry]

    public init(
        name: String,
        siteClass: IRTechSiteClass? = nil,
        width: Double? = nil,
        height: Double? = nil,
        symmetry: [IRTechSymmetry] = []
    ) {
        self.name = name
        self.siteClass = siteClass
        self.width = width
        self.height = height
        self.symmetry = symmetry
    }
}
