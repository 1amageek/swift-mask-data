import LayoutIR

/// Event-driven scanline over band decompositions.
///
/// Visits each distinct y-row once with the bands covering it: bands enter
/// the active set at their `yMin` row and leave at their `yMax` row. Total
/// work is O(n log n + Σ active-per-row) instead of the O(rows × n) full
/// rescan of testing every band against every row.
enum ScanlineSweep {
    enum SweepError: Error, Equatable, CustomStringConvertible {
        case invalidBand(input: String, index: Int, xMin: Int32, xMax: Int32, yMin: Int32, yMax: Int32)

        var description: String {
            switch self {
            case .invalidBand(let input, let index, let xMin, let xMax, let yMin, let yMax):
                return "Invalid scanline band in \(input)[\(index)]: x=[\(xMin), \(xMax)), y=[\(yMin), \(yMax))."
            }
        }
    }

    /// Visits every row `[yMin, yMax)` between consecutive distinct y
    /// boundaries of `a` and `b` combined, passing the x-intervals of the
    /// bands from each set that cover the row. Bands always span whole rows
    /// because every band boundary is itself a row boundary.
    static func checkedSweepRows(
        _ a: [RegionBoolean.Band],
        _ b: [RegionBoolean.Band],
        chargeWork: () throws -> Void = {},
        checkCancellation: () throws -> Void = {},
        _ body: (
            _ yMin: Int32,
            _ yMax: Int32,
            _ aIntervals: [RegionBoolean.Interval],
            _ bIntervals: [RegionBoolean.Interval]
        ) throws -> Void
    ) throws {
        try checkCancellation()
        try validateBands(a, input: "a", chargeWork: chargeWork, checkCancellation: checkCancellation)
        try validateBands(b, input: "b", chargeWork: chargeWork, checkCancellation: checkCancellation)

        var ys = Set<Int32>()
        for operand in [a, b] {
            for band in operand {
                try checkCancellation()
                try chargeWork()
                ys.insert(band.yMin); ys.insert(band.yMax)
            }
        }
        try checkCancellation()
        let sortedYs = ys.sorted()
        try checkCancellation()
        guard sortedYs.count >= 2 else { return }

        var startersAByY: [Int32: [RegionBoolean.Band]] = [:]
        var startersBByY: [Int32: [RegionBoolean.Band]] = [:]
        startersAByY.reserveCapacity(a.count)
        startersBByY.reserveCapacity(b.count)
        for band in a {
            try checkCancellation()
            try chargeWork()
            startersAByY[band.yMin, default: []].append(band)
        }
        for band in b {
            try checkCancellation()
            try chargeWork()
            startersBByY[band.yMin, default: []].append(band)
        }

        var activeA: [RegionBoolean.Band] = []
        var activeB: [RegionBoolean.Band] = []
        func evict(_ active: inout [RegionBoolean.Band], at y: Int32) throws {
            var retained = 0
            for index in active.indices {
                try checkCancellation()
                try chargeWork()
                if active[index].yMax > y {
                    active[retained] = active[index]
                    retained += 1
                }
            }
            active.removeLast(active.count - retained)
        }
        func insert(_ starters: [RegionBoolean.Band], into active: inout [RegionBoolean.Band]) throws {
            for band in starters {
                try checkCancellation()
                try chargeWork()
                active.append(band)
            }
        }
        func intervals(_ active: [RegionBoolean.Band]) throws -> [RegionBoolean.Interval] {
            var result: [RegionBoolean.Interval] = []
            result.reserveCapacity(active.count)
            for band in active {
                try checkCancellation()
                try chargeWork()
                result.append(RegionBoolean.Interval(lo: band.xMin, hi: band.xMax))
            }
            return result
        }
        for rowIndex in 0..<(sortedYs.count - 1) {
            try checkCancellation()
            let yMin = sortedYs[rowIndex]
            let yMax = sortedYs[rowIndex + 1]
            try evict(&activeA, at: yMin)
            try evict(&activeB, at: yMin)
            try insert(startersAByY[yMin] ?? [], into: &activeA)
            try insert(startersBByY[yMin] ?? [], into: &activeB)
            try body(yMin, yMax, intervals(activeA), intervals(activeB))
        }
        try checkCancellation()
    }

    private static func validateBands(_ bands: [RegionBoolean.Band], input: String,
        chargeWork: () throws -> Void, checkCancellation: () throws -> Void
    ) throws {
        for (index, band) in bands.enumerated() {
            try checkCancellation()
            try chargeWork()
            guard band.xMin < band.xMax, band.yMin < band.yMax else {
                throw SweepError.invalidBand(
                    input: input,
                    index: index,
                    xMin: band.xMin,
                    xMax: band.xMax,
                    yMin: band.yMin,
                    yMax: band.yMax
                )
            }
        }
    }
}
