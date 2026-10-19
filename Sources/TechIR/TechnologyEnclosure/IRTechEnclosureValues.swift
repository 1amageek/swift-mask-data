/// Enclosure overhang values for via definitions.
public struct IRTechEnclosureValues: Hashable, Sendable, Codable {
    public var overhang1: Double
    public var overhang2: Double

    public init(overhang1: Double, overhang2: Double) {
        self.overhang1 = overhang1
        self.overhang2 = overhang2
    }
}
