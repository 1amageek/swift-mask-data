import LayoutIR

/// Event-driven scanline over band decompositions.
///
/// Visits each distinct y-row once with the bands covering it: bands enter
/// the active set at their `yMin` row and leave at their `yMax` row. Total
/// work is O(n log n + Σ active-per-row) instead of the O(rows × n) full
/// rescan of testing every band against every row.
enum ScanlineSweep {

    /// Visits every row `[yMin, yMax)` between consecutive distinct y
    /// boundaries of `a` and `b` combined, passing the x-intervals of the
    /// bands from each set that cover the row. Bands always span whole rows
    /// because every band boundary is itself a row boundary.
    static func sweepRows(
        _ a: [RegionBoolean.Band],
        _ b: [RegionBoolean.Band],
        _ body: (
            _ yMin: Int32,
            _ yMax: Int32,
            _ aIntervals: [RegionBoolean.Interval],
            _ bIntervals: [RegionBoolean.Interval]
        ) -> Void
    ) {
        var ys = Set<Int32>()
        for band in a { ys.insert(band.yMin); ys.insert(band.yMax) }
        for band in b { ys.insert(band.yMin); ys.insert(band.yMax) }
        let sortedYs = ys.sorted()
        guard sortedYs.count >= 2 else { return }

        var rowIndexByY: [Int32: Int] = [:]
        rowIndexByY.reserveCapacity(sortedYs.count)
        for (index, y) in sortedYs.enumerated() { rowIndexByY[y] = index }

        var startersA = Array(repeating: [RegionBoolean.Band](), count: sortedYs.count)
        var startersB = Array(repeating: [RegionBoolean.Band](), count: sortedYs.count)
        for band in a where band.yMin < band.yMax {
            startersA[rowIndexByY[band.yMin]!].append(band)
        }
        for band in b where band.yMin < band.yMax {
            startersB[rowIndexByY[band.yMin]!].append(band)
        }

        var activeA: [RegionBoolean.Band] = []
        var activeB: [RegionBoolean.Band] = []
        for rowIndex in 0..<(sortedYs.count - 1) {
            let yMin = sortedYs[rowIndex]
            let yMax = sortedYs[rowIndex + 1]
            activeA.removeAll { $0.yMax <= yMin }
            activeB.removeAll { $0.yMax <= yMin }
            activeA.append(contentsOf: startersA[rowIndex])
            activeB.append(contentsOf: startersB[rowIndex])
            body(
                yMin,
                yMax,
                activeA.map { RegionBoolean.Interval(lo: $0.xMin, hi: $0.xMax) },
                activeB.map { RegionBoolean.Interval(lo: $0.xMin, hi: $0.xMax) }
            )
        }
    }
}
