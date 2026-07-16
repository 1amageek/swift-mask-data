import Testing
import LayoutIR
@testable import MaskGeometry

@Suite("MaskGeometry Bug Fixes")
struct MaskGeometryBugFixTests {

    @Test func testOctagonalSizingCorrectArea() throws {
        // Create a square polygon 0,0 -> 1000,1000
        let box = IRBoundary(layer: 1, datatype: 0, points: [
            IRPoint(x: 0, y: 0), IRPoint(x: 1000, y: 0),
            IRPoint(x: 1000, y: 1000), IRPoint(x: 0, y: 1000),
            IRPoint(x: 0, y: 0),
        ], properties: [])

        let region = Region(layer: 1, polygons: [box])
        let amount: Int32 = 100

        // Size with square corners (reference maximum)
        let squareResult = try region.sized(by: amount, cornerMode: .square)
        let squareArea = squareResult.area

        // Size with octagonal corners
        let octResult = try region.sized(by: amount, cornerMode: .octagonal)
        let octArea = octResult.area

        // Size with round corners (reference minimum, high segment count)
        let roundResult = try region.sized(by: amount, cornerMode: .round(segments: 16))
        let roundArea = roundResult.area

        // Octagonal area should be between round and square
        // Square sizing of 1000x1000 by 100 -> 1200x1200 = 1,440,000
        // Round would be slightly less due to rounded corners
        // Octagonal should be between the two
        #expect(squareArea > 0)
        #expect(octArea > 0)
        #expect(roundArea > 0)
        #expect(octArea <= squareArea, "Octagonal area should not exceed square area")
        #expect(octArea >= roundArea, "Octagonal area should be at least as large as round area")

        // Verify octagonal area is close to expected
        // For a 1000x1000 box sized by 100 with octagonal corners:
        // The resulting shape is 1200x1200 with chamfered corners
        // Each corner chamfer removes a small triangle compared to square
        let expectedSquareArea: Int64 = 1200 * 1200
        #expect(squareArea == expectedSquareArea)
        // Octagonal should be at least 95% of square area (corner chamfers are small)
        #expect(Double(octArea) > Double(squareArea) * 0.95)
    }

    @Test func testGridCheckNegativeCoordinates() throws {
        // Polygon entirely in negative coordinate space, on grid
        let onGridPoly = IRBoundary(layer: 1, datatype: 0, points: [
            IRPoint(x: -100, y: -100), IRPoint(x: -50, y: -100),
            IRPoint(x: -50, y: -50), IRPoint(x: -100, y: -50),
            IRPoint(x: -100, y: -100),
        ], properties: [])

        let onGridRegion = Region(layer: 1, polygons: [onGridPoly])
        let violations = onGridRegion.gridViolations(gridX: 10, gridY: 10)
        #expect(violations.isEmpty, "All vertices on 10-unit grid should have no violations")

        // Polygon with some vertices off grid in negative space
        let offGridPoly = IRBoundary(layer: 1, datatype: 0, points: [
            IRPoint(x: -103, y: -100), IRPoint(x: -50, y: -100),
            IRPoint(x: -50, y: -50), IRPoint(x: -103, y: -50),
            IRPoint(x: -103, y: -100),
        ], properties: [])

        let offGridRegion = Region(layer: 1, polygons: [offGridPoly])
        let offViolations = offGridRegion.gridViolations(gridX: 10, gridY: 10)
        #expect(!offViolations.isEmpty, "Vertices at x=-103 should be off 10-unit grid")

        // Mixed positive and negative coordinates, all on grid
        let mixedOnGrid = IRBoundary(layer: 1, datatype: 0, points: [
            IRPoint(x: -20, y: -30), IRPoint(x: 40, y: -30),
            IRPoint(x: 40, y: 50), IRPoint(x: -20, y: 50),
            IRPoint(x: -20, y: -30),
        ], properties: [])

        let mixedRegion = Region(layer: 1, polygons: [mixedOnGrid])
        let mixedViolations = mixedRegion.gridViolations(gridX: 10, gridY: 10)
        #expect(mixedViolations.isEmpty, "All vertices on 10-unit grid should have no violations")
    }

    /// Regression: `unionBands` must be canonical. The scanline sweep splits
    /// rows at every y-coordinate in the region, so without the vertical
    /// re-merge a feature's bands would fragment differently depending on
    /// what unrelated geometry happens to share the region — downstream
    /// width/spacing checks then report different marker boxes for the same
    /// feature.
    @Test func testUnionBandsCanonicalAgainstUnrelatedRows() throws {
        func rect(_ xMin: Int32, _ yMin: Int32, _ xMax: Int32, _ yMax: Int32) -> IRBoundary {
            IRBoundary(layer: 1, datatype: 0, points: [
                IRPoint(x: xMin, y: yMin), IRPoint(x: xMax, y: yMin),
                IRPoint(x: xMax, y: yMax), IRPoint(x: xMin, y: yMax),
                IRPoint(x: xMin, y: yMin),
            ], properties: [])
        }
        let tall = rect(0, 0, 100, 1000)
        // Far-away small rectangle whose y-extent (300...400) splits the
        // global sweep rows inside the tall rectangle's span.
        let splitter = rect(5000, 300, 5100, 400)

        let bands = { (region: Region) throws in
            try RegionBoolean.unionBands(region).map {
                [$0.xMin, $0.xMax, $0.yMin, $0.yMax]
            }.sorted { $0.lexicographicallyPrecedes($1) }
        }

        let alone = try bands(Region(layer: 1, polygons: [tall]))
        let together = try bands(Region(layer: 1, polygons: [tall, splitter]))
        #expect(alone == [[0, 100, 0, 1000]], "a lone rectangle must be exactly one band")
        #expect(
            together == [[0, 100, 0, 1000], [5000, 5100, 300, 400]],
            "unrelated rows must not fragment another feature's bands"
        )

        // Two stacked abutting rectangles with the same x-extent are one
        // feature and must merge into a single band.
        let stacked = Region(layer: 1, polygons: [rect(0, 0, 100, 500), rect(0, 500, 100, 1000)])
        #expect(try bands(stacked) == [[0, 100, 0, 1000]], "stacked same-x rows must merge")
    }

    @Test func scanlineSweepRejectsInvalidBands() throws {
        #expect(throws: ScanlineSweep.SweepError.invalidBand(
            input: "a",
            index: 0,
            xMin: 0,
            xMax: 0,
            yMin: 0,
            yMax: 10
        )) {
            try ScanlineSweep.checkedSweepRows(
                [RegionBoolean.Band(xMin: 0, xMax: 0, yMin: 0, yMax: 10)],
                []
            ) { _, _, _, _ in }
        }

        #expect(throws: ScanlineSweep.SweepError.invalidBand(
            input: "b",
            index: 0,
            xMin: 0,
            xMax: 10,
            yMin: 10,
            yMax: 10
        )) {
            try ScanlineSweep.checkedSweepRows(
                [],
                [RegionBoolean.Band(xMin: 0, xMax: 10, yMin: 10, yMax: 10)]
            ) { _, _, _, _ in }
        }
    }
}
