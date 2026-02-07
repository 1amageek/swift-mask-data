import Testing
import LayoutIR
@testable import GeometryOps

@Suite("GeometryOps Bug Fixes")
struct GeometryOpsBugFixTests {

    @Test func testOctagonalSizingCorrectArea() {
        // Create a square polygon 0,0 -> 1000,1000
        let box = IRBoundary(layer: 1, datatype: 0, points: [
            IRPoint(x: 0, y: 0), IRPoint(x: 1000, y: 0),
            IRPoint(x: 1000, y: 1000), IRPoint(x: 0, y: 1000),
            IRPoint(x: 0, y: 0),
        ], properties: [])

        let region = Region(layer: 1, polygons: [box])
        let amount: Int32 = 100

        // Size with square corners (reference maximum)
        let squareResult = region.sized(by: amount, cornerMode: .square)
        let squareArea = squareResult.area

        // Size with octagonal corners
        let octResult = region.sized(by: amount, cornerMode: .octagonal)
        let octArea = octResult.area

        // Size with round corners (reference minimum, high segment count)
        let roundResult = region.sized(by: amount, cornerMode: .round(segments: 16))
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

    @Test func testGridCheckNegativeCoordinates() {
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
}
