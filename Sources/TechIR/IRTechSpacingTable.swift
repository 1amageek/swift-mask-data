/// Width-dependent spacing table for a layer.
public struct IRTechSpacingTable: Hashable, Sendable, Codable {
    public var entries: [IRTechSpacingWidthEntry]

    public init(entries: [IRTechSpacingWidthEntry]) {
        self.entries = entries
    }
}

/// A single entry mapping a minimum width to its required spacing.
public struct IRTechSpacingWidthEntry: Hashable, Sendable, Codable {
    public var width: Double
    public var spacing: Double

    public init(width: Double, spacing: Double) {
        self.width = width
        self.spacing = spacing
    }
}
