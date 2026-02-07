/// Represents a REGIONS entry in DEF.
public struct DEFRegion: Hashable, Sendable, Codable {
    public var name: String
    public var rects: [DEFRect]
    public var regionType: RegionType?

    public enum RegionType: String, Hashable, Sendable, Codable {
        case fence = "FENCE"
        case guide = "GUIDE"
    }

    public init(name: String, rects: [DEFRect] = [], regionType: RegionType? = nil) {
        self.name = name
        self.rects = rects
        self.regionType = regionType
    }
}
