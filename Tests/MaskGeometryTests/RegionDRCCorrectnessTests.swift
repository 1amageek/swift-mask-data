import Testing
import LayoutIR
@testable import MaskGeometry

// MARK: - Self Spacing

@Suite("Region Self Spacing")
struct RegionSelfSpacingTests {

    @Test func overlappingPolygonsDoNotFlag() {
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 50, y1: 0, x2: 150, y2: 100),
        ])
        #expect(r.selfSpaceViolations(minSpace: 20).isEmpty)
    }

    @Test func abuttingPolygonsDoNotFlag() {
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 100, y1: 0, x2: 200, y2: 100),
        ])
        #expect(r.selfSpaceViolations(minSpace: 20).isEmpty)
    }

    @Test func narrowGapBetweenPolygonsFlags() {
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 110, y1: 0, x2: 210, y2: 100),
        ])
        let violations = r.selfSpaceViolations(minSpace: 20)
        #expect(violations.count == 1)
        let xs = Set(violations.flatMap { [$0.edge1.p1.x, $0.edge2.p1.x] })
        #expect(xs == [100, 110])
    }

    @Test func gapFullyBridgedByThirdShapeDoesNotFlag() {
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 110, y1: 0, x2: 210, y2: 100),
            makeBox(x1: 95, y1: 0, x2: 115, y2: 100),
        ])
        #expect(r.selfSpaceViolations(minSpace: 20).isEmpty)
    }

    @Test func singlePolygonWidthIsNotFlaggedAsSpacing() {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 10, y2: 100)])
        #expect(r.selfSpaceViolations(minSpace: 20).isEmpty)
    }

    @Test func notchInsideSingleComponentFlagsAsSpacing() {
        // U-shape: two 100-wide arms separated by a 100-wide notch.
        let u = IRBoundary(layer: 1, datatype: 0, points: [
            IRPoint(x: 0, y: 0), IRPoint(x: 300, y: 0),
            IRPoint(x: 300, y: 300), IRPoint(x: 200, y: 300),
            IRPoint(x: 200, y: 100), IRPoint(x: 100, y: 100),
            IRPoint(x: 100, y: 300), IRPoint(x: 0, y: 300),
            IRPoint(x: 0, y: 0),
        ], properties: [])
        let r = Region(layer: 1, polygons: [u])

        let violations = r.selfSpaceViolations(minSpace: 150)
        #expect(violations.count == 1)
        // The notch gap spans x 100..200; arm widths (100 < 150) must not flag.
        let xs = Set(violations.flatMap { [$0.edge1.p1.x, $0.edge2.p1.x] })
        #expect(xs == [100, 200])
    }

    @Test func diagonalCornerGapFlags() {
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 110, y1: 110, x2: 210, y2: 210),
        ])
        // Corner distance = sqrt(10^2 + 10^2) ≈ 14.14 < 20.
        let violations = r.selfSpaceViolations(minSpace: 20)
        #expect(violations.count == 1)
    }

    @Test func diagonalCornerGapUsesExactEuclideanDistance() {
        // Corner distance = sqrt(3^2 + 4^2) = 5 exactly.
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 103, y1: 104, x2: 200, y2: 200),
        ])
        #expect(r.selfSpaceViolations(minSpace: 5).isEmpty)
        #expect(r.selfSpaceViolations(minSpace: 6).count == 1)
    }
}

// MARK: - Connectivity

@Suite("Region Connectivity")
struct RegionConnectivityTests {

    @Test func disjointPolygonsAreSeparateComponents() {
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 200, y1: 0, x2: 300, y2: 100),
        ])
        let components = r.connectedComponents()
        #expect(components.count == 2)
        #expect(components.allSatisfy { $0.area == 10000 })
    }

    @Test func edgeAbuttingPolygonsAreOneComponent() {
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 100, y1: 0, x2: 200, y2: 100),
        ])
        let components = r.connectedComponents()
        #expect(components.count == 1)
        #expect(components.first?.area == 20000)
    }

    @Test func cornerTouchingPolygonsAreSeparateComponents() {
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 100, y1: 100, x2: 200, y2: 200),
        ])
        #expect(r.connectedComponents().count == 2)
    }

    @Test func mergedLShapeSpanningMultiplePolygonsIsOneComponent() {
        // After a boolean merge an L-shape becomes stacked rectangles in
        // separate polygons; component analysis must reunite them.
        let merged = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 200, y2: 100)])
            .or(Region(layer: 1, polygons: [makeBox(x1: 0, y1: 100, x2: 100, y2: 200)]))
        let components = merged.connectedComponents()
        #expect(components.count == 1)
        #expect(components.first?.area == 30000)
    }

    @Test func donutHasOneHole() {
        let outer = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 300, y2: 300)])
        let inner = Region(layer: 1, polygons: [makeBox(x1: 100, y1: 100, x2: 200, y2: 200)])
        let donut = outer.not(inner)
        let holes = donut.holes()
        #expect(holes.count == 1)
        #expect(holes.first?.area == 10000)
    }

    @Test func solidRectangleHasNoHoles() {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        #expect(r.holes().isEmpty)
    }

    @Test func containsIsBoundaryInclusive() {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        #expect(r.contains(IRPoint(x: 50, y: 50)))
        #expect(r.contains(IRPoint(x: 0, y: 50)))
        #expect(r.contains(IRPoint(x: 100, y: 100)))
        #expect(!r.contains(IRPoint(x: 101, y: 50)))
    }
}

// MARK: - Sizing Exactness

@Suite("Region Sizing Exactness")
struct RegionSizingExactnessTests {

    @Test func dilationDoesNotFillConcavities() {
        let l = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 200, y2: 100),
            makeBox(x1: 0, y1: 100, x2: 100, y2: 200),
        ])
        let dilated = l.sized(by: 10)
        let expected = Region(layer: 1, polygons: [makeBox(x1: -10, y1: -10, x2: 210, y2: 110)])
            .or(Region(layer: 1, polygons: [makeBox(x1: -10, y1: 90, x2: 110, y2: 210)]))
        #expect(dilated.xor(expected).isEmpty)
        #expect(dilated.area == 38400)
    }

    @Test func erosionIsExactSquareErosion() {
        let l = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 200, y2: 100),
            makeBox(x1: 0, y1: 100, x2: 100, y2: 200),
        ])
        let eroded = l.sized(by: -20)
        let expected = Region(layer: 1, polygons: [makeBox(x1: 20, y1: 20, x2: 180, y2: 80)])
            .or(Region(layer: 1, polygons: [makeBox(x1: 20, y1: 20, x2: 80, y2: 180)]))
        #expect(eroded.xor(expected).isEmpty)
        #expect(eroded.area == 15600)
    }

    @Test func openingRemovesNarrowArm() {
        // Wide base with a narrow arm: opening with radius 50 must remove
        // the 80-wide arm and keep the base intact.
        let shape = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 400, y2: 200),
            makeBox(x1: 0, y1: 200, x2: 80, y2: 400),
        ])
        let opened = shape.sized(by: -50).sized(by: 50)
        let expected = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 400, y2: 200)])
        #expect(opened.xor(expected).isEmpty)
        #expect(opened.area == 80000)
    }

    @Test func erosionThatConsumesEverythingIsEmpty() {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 30, y2: 30)])
        #expect(r.sized(by: -20).isEmpty)
    }
}

// MARK: - Enclosure Robustness

@Suite("Region Enclosure Robustness")
struct RegionEnclosureRobustnessTests {

    @Test func innerCompletelyOutsideOuterIsViolation() {
        let outer = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let inner = Region(layer: 2, polygons: [makeBox(layer: 2, x1: 300, y1: 300, x2: 400, y2: 400)])
        let violations = outer.enclosureViolations(inner: inner, minEnclosure: 10)
        #expect(!violations.isEmpty)
    }

    @Test func innerPartiallyOutsideOuterIsViolation() {
        let outer = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let inner = Region(layer: 2, polygons: [makeBox(layer: 2, x1: 50, y1: 50, x2: 150, y2: 150)])
        let violations = outer.enclosureViolations(inner: inner, minEnclosure: 10)
        #expect(!violations.isEmpty)
    }

    @Test func wellEnclosedInnerPasses() {
        let outer = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let inner = Region(layer: 2, polygons: [makeBox(layer: 2, x1: 20, y1: 20, x2: 80, y2: 80)])
        #expect(outer.enclosureViolations(inner: inner, minEnclosure: 20).isEmpty)
    }
}

// MARK: - Width on Union Coverage

@Suite("Region Width Union Coverage")
struct RegionWidthUnionCoverageTests {

    /// Two wide segments of one feature overlapping with a tiny vertical
    /// offset: the union's stacked-rectangle seam must not read as a
    /// sliver-thin band. Local coverage everywhere is at least 280.
    @Test func staircaseOverlapDoesNotFlagWidth() {
        let first = makeBox(x1: 20, y1: 3070, x2: 450, y2: 3350)
        let second = makeBox(x1: 400, y1: 3080, x2: 7760, y2: 3360)
        let merged = Region(layer: 1, polygons: [first]).or(Region(layer: 1, polygons: [second]))
        #expect(merged.widthViolations(minWidth: 280).isEmpty)
    }

    /// A genuinely narrow protrusion on top of wide metal must still flag:
    /// its left/right edges are true boundaries 100 apart.
    @Test func narrowProtrusionOnWideMetalFlagsWidth() {
        let base = makeBox(x1: 0, y1: 0, x2: 1000, y2: 500)
        let jog = makeBox(x1: 400, y1: 500, x2: 500, y2: 600)
        let merged = Region(layer: 1, polygons: [base]).or(Region(layer: 1, polygons: [jog]))
        let violations = merged.widthViolations(minWidth: 280)
        #expect(violations.count == 1)
        let xs = violations.flatMap { [$0.edge1.p1.x, $0.edge2.p1.x] }.sorted()
        #expect(xs == [400, 500])
    }

    /// Abutting (edge-sharing, non-overlapping) segments with an offset also
    /// form one feature whose seam must not flag.
    @Test func abuttingOffsetSegmentsDoNotFlagWidth() {
        let first = makeBox(x1: 0, y1: 0, x2: 500, y2: 300)
        let second = makeBox(x1: 500, y1: 10, x2: 1000, y2: 310)
        let merged = Region(layer: 1, polygons: [first]).or(Region(layer: 1, polygons: [second]))
        #expect(merged.widthViolations(minWidth: 280).isEmpty)
    }
}
