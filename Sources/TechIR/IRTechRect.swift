/// Axis-aligned rectangle in microns.
public struct IRTechRect: Hashable, Sendable, Codable {
    public var x1: Double
    public var y1: Double
    public var x2: Double
    public var y2: Double

    public init(x1: Double, y1: Double, x2: Double, y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }
}
