/// Exclusively borrowed aggregate admission; failed calls retain spent resources.
public struct RectilinearUnionBudget: Equatable, Sendable {
    public private(set) var remainingInputEntries: Int
    public private(set) var remainingEdgeProbes: Int
    public private(set) var remainingIntermediateBands: Int
    public private(set) var remainingSweepWork: Int
    public private(set) var remainingOutputBands: Int

    public init(limits: RectilinearUnionLimits) throws {
        guard limits.maximumInputEntries >= 0, limits.maximumEdgeProbes >= 0,
              limits.maximumIntermediateBands >= 0, limits.maximumSweepWork >= 0,
              limits.maximumOutputBands >= 0 else {
            throw RectilinearDecompositionError.invalidLimits
        }
        remainingInputEntries = limits.maximumInputEntries
        remainingEdgeProbes = limits.maximumEdgeProbes
        remainingIntermediateBands = limits.maximumIntermediateBands
        remainingSweepWork = limits.maximumSweepWork
        remainingOutputBands = limits.maximumOutputBands
    }

    mutating func spend(_ resource: RectilinearDecompositionError.Resource, amount: Int = 1) throws {
        func remainder(_ available: Int) throws -> Int {
            guard amount >= 0, amount <= available else {
                throw RectilinearDecompositionError.limitExceeded(resource)
            }
            return available - amount
        }
        switch resource {
        case .inputEntries: remainingInputEntries = try remainder(remainingInputEntries)
        case .edgeProbes: remainingEdgeProbes = try remainder(remainingEdgeProbes)
        case .intermediateBands: remainingIntermediateBands = try remainder(remainingIntermediateBands)
        case .sweepWork: remainingSweepWork = try remainder(remainingSweepWork)
        case .outputBands: remainingOutputBands = try remainder(remainingOutputBands)
        }
    }
}
