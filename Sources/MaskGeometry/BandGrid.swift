import LayoutIR

/// Uniform-grid spatial index over band bounding boxes.
///
/// Queries return the indices of bands that could lie within `margin` of a
/// probe band, so pair checks (spacing, corner distance, touch) only visit
/// geometric neighbours instead of every band pair. Results are a superset
/// of the true neighbours — exact pair predicates stay at the caller — and
/// are returned in ascending index order so callers preserve the emission
/// order of the full nested-loop scan they replace.
struct BandGrid {

    private let cellSize: Int64
    private var cells: [UInt64: [Int32]] = [:]

    /// Cell size adapts to both the query margin and the band sizes: cells
    /// several margins wide keep query fanout low, while cells no smaller
    /// than the mean band dimension keep the insertion fanout bounded for
    /// large bands (a small fixed cell would shatter a long wire band into
    /// hundreds of thousands of cells when the margin is tiny, as in
    /// touch-connectivity queries with margin 1).
    init(bands: [RegionBoolean.Band], margin: Int32) {
        var meanDimension: Int64 = 0
        if !bands.isEmpty {
            var total = 0.0
            for band in bands {
                let width = Int64(band.xMax) - Int64(band.xMin)
                let height = Int64(band.yMax) - Int64(band.yMin)
                total += Double(max(width, height))
            }
            meanDimension = Int64((total / Double(bands.count)).rounded(.up))
        }
        cellSize = max(Int64(max(margin, 1)) * 8, meanDimension, 1)
        for (index, band) in bands.enumerated() {
            forEachCell(
                xMin: Int64(band.xMin), xMax: Int64(band.xMax),
                yMin: Int64(band.yMin), yMax: Int64(band.yMax)
            ) { key in
                cells[key, default: []].append(Int32(index))
            }
        }
    }

    /// Ascending, duplicate-free indices of bands whose cells intersect the
    /// probe band expanded by `margin`.
    func candidateIndices(near band: RegionBoolean.Band, margin: Int32) -> [Int] {
        var found: [Int32] = []
        forEachCell(
            xMin: Int64(band.xMin) - Int64(margin), xMax: Int64(band.xMax) + Int64(margin),
            yMin: Int64(band.yMin) - Int64(margin), yMax: Int64(band.yMax) + Int64(margin)
        ) { key in
            if let indices = cells[key] {
                found.append(contentsOf: indices)
            }
        }
        found.sort()
        var result: [Int] = []
        result.reserveCapacity(found.count)
        var previous: Int32? = nil
        for index in found where index != previous {
            result.append(Int(index))
            previous = index
        }
        return result
    }

    private func forEachCell(
        xMin: Int64, xMax: Int64,
        yMin: Int64, yMax: Int64,
        _ body: (UInt64) -> Void
    ) {
        let cxMin = floorDiv(xMin), cxMax = floorDiv(xMax)
        let cyMin = floorDiv(yMin), cyMax = floorDiv(yMax)
        for cx in cxMin...cxMax {
            for cy in cyMin...cyMax {
                body(cellKey(cx, cy))
            }
        }
    }

    private func floorDiv(_ value: Int64) -> Int64 {
        value >= 0 ? value / cellSize : (value - cellSize + 1) / cellSize
    }

    /// Coordinates are Int32 and cells are ≥ 8 dbu, so cell coordinates fit
    /// comfortably in 32 bits each.
    private func cellKey(_ cx: Int64, _ cy: Int64) -> UInt64 {
        (UInt64(UInt32(truncatingIfNeeded: cx)) << 32) | UInt64(UInt32(truncatingIfNeeded: cy))
    }
}
