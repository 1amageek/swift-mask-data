/// Explicit caller policy for one aggregate union generation.
public struct RectilinearUnionLimits: Equatable, Sendable {
    public let maximumInputEntries: Int
    public let maximumEdgeProbes: Int
    public let maximumIntermediateBands: Int
    public let maximumSweepWork: Int
    public let maximumOutputBands: Int

    public init(maximumInputEntries: Int, maximumEdgeProbes: Int,
                maximumIntermediateBands: Int, maximumSweepWork: Int, maximumOutputBands: Int) {
        self.maximumInputEntries = maximumInputEntries
        self.maximumEdgeProbes = maximumEdgeProbes
        self.maximumIntermediateBands = maximumIntermediateBands
        self.maximumSweepWork = maximumSweepWork
        self.maximumOutputBands = maximumOutputBands
    }
}
