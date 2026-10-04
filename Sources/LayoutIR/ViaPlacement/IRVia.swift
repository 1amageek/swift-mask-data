/// An immutable placement of a named technology via, without fabricated wire geometry.
public struct IRVia: Hashable, Sendable, Codable {
    public let viaName: String
    public let origin: IRPoint
    public let transform: IRTransform
    public let routeLayer: Int16
    public let properties: [IRProperty]

    public init(viaName: String, origin: IRPoint, transform: IRTransform = .identity,
                routeLayer: Int16, properties: [IRProperty] = []) {
        self.viaName = viaName
        self.origin = origin
        self.transform = transform
        self.routeLayer = routeLayer
        self.properties = properties
    }
}
