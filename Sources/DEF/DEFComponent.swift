public struct DEFComponent: Hashable, Sendable, Codable {
    public var name: String
    public var macro: String
    public var x: Int32
    public var y: Int32
    public var orientation: DEFOrientation
    public var placementStatus: PlacementStatus?
    public var weight: Int?
    public var region: String?
    public var source: String?
    public var properties: [DEFProperty]

    public enum PlacementStatus: String, Hashable, Sendable, Codable {
        case placed = "PLACED"
        case fixed = "FIXED"
        case cover = "COVER"
        case unplaced = "UNPLACED"
    }

    public init(name: String, macro: String, x: Int32 = 0, y: Int32 = 0,
                orientation: DEFOrientation = .n,
                placementStatus: PlacementStatus? = nil,
                weight: Int? = nil, region: String? = nil,
                source: String? = nil, properties: [DEFProperty] = []) {
        self.name = name
        self.macro = macro
        self.x = x
        self.y = y
        self.orientation = orientation
        self.placementStatus = placementStatus
        self.weight = weight
        self.region = region
        self.source = source
        self.properties = properties
    }
}

public enum DEFOrientation: String, Hashable, Sendable, Codable, CaseIterable {
    case n = "N"
    case s = "S"
    case e = "E"
    case w = "W"
    case fn = "FN"
    case fs = "FS"
    case fe = "FE"
    case fw = "FW"
}
