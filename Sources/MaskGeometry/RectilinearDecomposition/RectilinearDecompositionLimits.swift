/// Caller-owned admission ceilings; defaults do not qualify workload performance.
public struct RectilinearDecompositionLimits: Equatable, Sendable {
    public let maximumInputEntries: Int
    public let maximumEdgeProbes: Int
    public let maximumOutputBands: Int

    public init(maximumInputEntries: Int, maximumEdgeProbes: Int, maximumOutputBands: Int) {
        self.maximumInputEntries = maximumInputEntries
        self.maximumEdgeProbes = maximumEdgeProbes
        self.maximumOutputBands = maximumOutputBands
    }

    public static let `default` = Self(maximumInputEntries: 1_000_000,
                                      maximumEdgeProbes: 8_000_000,
                                      maximumOutputBands: 1_000_000)
}
