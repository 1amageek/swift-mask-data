/// Minimum cut-count rule between two conductor layers.
public struct IRTechMinimumCutRule: Hashable, Sendable, Codable {
    public var name: String
    public var cutLayerName: String
    public var bottomLayerName: String
    public var topLayerName: String
    public var minimumCount: Int

    public init(
        name: String,
        cutLayerName: String,
        bottomLayerName: String,
        topLayerName: String,
        minimumCount: Int
    ) {
        self.name = name
        self.cutLayerName = cutLayerName
        self.bottomLayerName = bottomLayerName
        self.topLayerName = topLayerName
        self.minimumCount = minimumCount
    }
}
