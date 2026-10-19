/// A via-generation formula, independent of any instantiated via geometry.
public struct IRTechViaGenerationRule: Hashable, Sendable, Codable {
    public struct RoutingLayer: Hashable, Sendable, Codable {
        public var layerName: String
        /// Opposing-side overhang pair in microns, without a chosen X/Y orientation.
        public var enclosure: IRTechEnclosureValues

        public init(layerName: String, enclosure: IRTechEnclosureValues) {
            self.layerName = layerName
            self.enclosure = enclosure
        }
    }

    public var name: String
    public var routingLayers: [RoutingLayer]
    public var cutLayerName: String
    /// Original cut location in microns, including any offset from the origin.
    public var cutRectangle: IRTechRect
    /// Explicit X/Y center-to-center spacing in microns, not an edge gap.
    public var cutCenterSpacing: IRTechAxisValue

    public init(name: String, routingLayers: [RoutingLayer], cutLayerName: String,
                cutRectangle: IRTechRect, cutCenterSpacing: IRTechAxisValue) {
        self.name = name
        self.routingLayers = routingLayers
        self.cutLayerName = cutLayerName
        self.cutRectangle = cutRectangle
        self.cutCenterSpacing = cutCenterSpacing
    }
}
