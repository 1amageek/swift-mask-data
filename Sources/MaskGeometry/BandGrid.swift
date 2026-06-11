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
    private let cells: [UInt64: [Int32]]

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
        let size = max(Int64(max(margin, 1)) * 8, meanDimension, 1)
        cellSize = size
        // Build into a local table and assign once: inserting through a
        // self-captured closure denies the optimizer unique ownership of
        // the stored dictionary, forcing a copy-on-write of the whole
        // table per insert and turning construction quadratic.
        var table: [UInt64: [Int32]] = [:]
        for (index, band) in bands.enumerated() {
            let cxMin = Self.floorDiv(Int64(band.xMin), by: size)
            let cxMax = Self.floorDiv(Int64(band.xMax), by: size)
            let cyMin = Self.floorDiv(Int64(band.yMin), by: size)
            let cyMax = Self.floorDiv(Int64(band.yMax), by: size)
            for cx in cxMin...cxMax {
                for cy in cyMin...cyMax {
                    table[Self.cellKey(cx, cy), default: []].append(Int32(index))
                }
            }
        }
        cells = table
    }

    /// Ascending, duplicate-free indices of bands whose cells intersect the
    /// probe band expanded by `margin`.
    func candidateIndices(near band: RegionBoolean.Band, margin: Int32) -> [Int] {
        var found: [Int32] = []
        let cxMin = Self.floorDiv(Int64(band.xMin) - Int64(margin), by: cellSize)
        let cxMax = Self.floorDiv(Int64(band.xMax) + Int64(margin), by: cellSize)
        let cyMin = Self.floorDiv(Int64(band.yMin) - Int64(margin), by: cellSize)
        let cyMax = Self.floorDiv(Int64(band.yMax) + Int64(margin), by: cellSize)
        for cx in cxMin...cxMax {
            for cy in cyMin...cyMax {
                if let indices = cells[Self.cellKey(cx, cy)] {
                    found.append(contentsOf: indices)
                }
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

    private static func floorDiv(_ value: Int64, by cellSize: Int64) -> Int64 {
        value >= 0 ? value / cellSize : (value - cellSize + 1) / cellSize
    }

    /// Coordinates are Int32 and cells are ≥ 8 dbu, so cell coordinates fit
    /// comfortably in 32 bits each.
    private static func cellKey(_ cx: Int64, _ cy: Int64) -> UInt64 {
        (UInt64(UInt32(truncatingIfNeeded: cx)) << 32) | UInt64(UInt32(truncatingIfNeeded: cy))
    }
}
