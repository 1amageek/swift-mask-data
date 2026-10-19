public struct LEFPortVia: Hashable, Sendable, Codable {
    public var viaName: String
    public var point: LEFPoint

    public init(viaName: String, point: LEFPoint) {
        self.viaName = viaName
        self.point = point
    }
}
