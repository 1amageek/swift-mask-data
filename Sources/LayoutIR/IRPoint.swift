public struct IRPoint: Hashable, Sendable, Codable {
    public var x: Int32
    public var y: Int32

    public init(x: Int32, y: Int32) {
        self.x = x
        self.y = y
    }

    public static let zero = IRPoint(x: 0, y: 0)
}
