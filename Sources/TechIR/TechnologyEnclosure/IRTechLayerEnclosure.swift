/// A cut-layer enclosure declaration with opposing-side overhangs in microns.
public struct IRTechLayerEnclosure: Hashable, Sendable, Codable {
    public enum Side: String, Hashable, Sendable, Codable {
        case above, below
    }

    /// Absence applies to both adjacent routing layers.
    public var side: Side?
    public var overhang1: Double
    public var overhang2: Double

    public init(overhang1: Double, overhang2: Double, side: Side? = nil) {
        self.side = side
        self.overhang1 = overhang1
        self.overhang2 = overhang2
    }
}
