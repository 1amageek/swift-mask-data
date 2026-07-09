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
        _ body: (
            _ yMin: Int32,
            _ yMax: Int32,
            _ aIntervals: [RegionBoolean.Interval],
            _ bIntervals: [RegionBoolean.Interval]
        ) -> Void
    ) throws {
        try validateBands(a, input: "a")
        try validateBands(b, input: "b")

        var ys = Set<Int32>()
        for band in a { ys.insert(band.yMin); ys.insert(band.yMax) }
        for band in b { ys.insert(band.yMin); ys.insert(band.yMax) }
        let sortedYs = ys.sorted()
        guard sortedYs.count >= 2 else { return }

        var startersAByY: [Int32: [RegionBoolean.Band]] = [:]
        var startersBByY: [Int32: [RegionBoolean.Band]] = [:]
        startersAByY.reserveCapacity(a.count)
        startersBByY.reserveCapacity(b.count)
        for band in a {
            startersAByY[band.yMin, default: []].append(band)
        }
        for band in b {
            startersBByY[band.yMin, default: []].append(band)
        }

        var activeA: [RegionBoolean.Band] = []
        var activeB: [RegionBoolean.Band] = []
        for rowIndex in 0..<(sortedYs.count - 1) {
            let yMin = sortedYs[rowIndex]
            let yMax = sortedYs[rowIndex + 1]
            activeA.removeAll { $0.yMax <= yMin }
            activeB.removeAll { $0.yMax <= yMin }
            activeA.append(contentsOf: startersAByY[yMin] ?? [])
            activeB.append(contentsOf: startersBByY[yMin] ?? [])
            body(
                yMin,
                yMax,
                activeA.map { RegionBoolean.Interval(lo: $0.xMin, hi: $0.xMax) },
                activeB.map { RegionBoolean.Interval(lo: $0.xMin, hi: $0.xMax) }
            )
        }
    }

    private static func validateBands(_ bands: [RegionBoolean.Band], input: String) throws {
        for (index, band) in bands.enumerated() {
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
