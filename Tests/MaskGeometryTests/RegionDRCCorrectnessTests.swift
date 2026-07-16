import Testing
import LayoutIR
@testable import MaskGeometry

// MARK: - Self Spacing

@Suite("Region Self Spacing")
struct RegionSelfSpacingTests {

    @Test func overlappingPolygonsDoNotFlag() throws {
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 50, y1: 0, x2: 150, y2: 100),
        ])
        #expect(try r.selfSpaceViolations(minSpace: 20).isEmpty)
    }

    @Test func abuttingPolygonsDoNotFlag() throws {
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 100, y1: 0, x2: 200, y2: 100),
        ])
        #expect(try r.selfSpaceViolations(minSpace: 20).isEmpty)
    }

    @Test func narrowGapBetweenPolygonsFlags() throws {
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 110, y1: 0, x2: 210, y2: 100),
        ])
        let violations = try r.selfSpaceViolations(minSpace: 20)
        #expect(violations.count == 1)
        let xs = Set(violations.flatMap { [$0.edge1.p1.x, $0.edge2.p1.x] })
        #expect(xs == [100, 110])
    }

    @Test func gapFullyBridgedByThirdShapeDoesNotFlag() throws {
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 110, y1: 0, x2: 210, y2: 100),
            makeBox(x1: 95, y1: 0, x2: 115, y2: 100),
        ])
        #expect(try r.selfSpaceViolations(minSpace: 20).isEmpty)
    }

    @Test func singlePolygonWidthIsNotFlaggedAsSpacing() throws {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 10, y2: 100)])
        #expect(try r.selfSpaceViolations(minSpace: 20).isEmpty)
    }

    @Test func stackedBandsOfOneMergedFeatureDoNotFlag() throws {
        // A route polyline over a bar: the merged feature decomposes into
        // stacked bands with differing x extents, and skip-a-row band
        // pairs show positive gaps that intermediate bands completely
        // fill. None of these interior gaps is a spacing violation.
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 1080, y1: 0, x2: 1420, y2: 2000),       // bar
            makeBox(x1: 1305, y1: 1885, x2: 24765, y2: 2115),   // leg 1
            makeBox(x1: 24535, y1: 1885, x2: 24765, y2: 2465),  // leg 2
            makeBox(x1: 24535, y1: 2235, x2: 25655, y2: 2465),  // leg 3
        ])
        #expect(try r.selfSpaceViolations(minSpace: 230).isEmpty)
    }

    @Test func stackedFeatureStillFlagsAgainstSeparateMetal() throws {
        // The interior-gap waiver must not silence a REAL gap between the
        // stacked feature and disconnected metal 115 < 230 away.
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 1080, y1: 0, x2: 1420, y2: 2000),
            makeBox(x1: 1305, y1: 1885, x2: 3000, y2: 2115),
            makeBox(x1: 3115, y1: 1885, x2: 4000, y2: 2115),    // 115 gap
        ])
        let violations = try r.selfSpaceViolations(minSpace: 230)
        #expect(!violations.isEmpty)
        let xs = Set(violations.flatMap { [$0.edge1.p1.x, $0.edge2.p1.x] })
        #expect(xs.contains(3000) && xs.contains(3115))
    }

    @Test func diagonalCornerGapFilledByMetalDoesNotFlag() throws {
        // Two boxes diagonally adjacent, with the diagonal box between
        // their corners completely covered by a third shape: connected
        // metal, not a corner gap.
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 110, y1: 110, x2: 210, y2: 210),
            makeBox(x1: 80, y1: 80, x2: 130, y2: 130),          // bridges the corner
        ])
        #expect(try r.selfSpaceViolations(minSpace: 30).isEmpty)
    }

    @Test func notchInsideSingleComponentFlagsAsSpacing() throws {
        // U-shape: two 100-wide arms separated by a 100-wide notch.
        let u = IRBoundary(layer: 1, datatype: 0, points: [
            IRPoint(x: 0, y: 0), IRPoint(x: 300, y: 0),
            IRPoint(x: 300, y: 300), IRPoint(x: 200, y: 300),
            IRPoint(x: 200, y: 100), IRPoint(x: 100, y: 100),
            IRPoint(x: 100, y: 300), IRPoint(x: 0, y: 300),
            IRPoint(x: 0, y: 0),
        ], properties: [])
        let r = Region(layer: 1, polygons: [u])

        let violations = try r.selfSpaceViolations(minSpace: 150)
        #expect(violations.count == 1)
        // The notch gap spans x 100..200; arm widths (100 < 150) must not flag.
        let xs = Set(violations.flatMap { [$0.edge1.p1.x, $0.edge2.p1.x] })
        #expect(xs == [100, 200])
    }

    @Test func diagonalCornerGapFlags() throws {
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 110, y1: 110, x2: 210, y2: 210),
        ])
        // Corner distance = sqrt(10^2 + 10^2) ≈ 14.14 < 20.
        let violations = try r.selfSpaceViolations(minSpace: 20)
        #expect(violations.count == 1)
    }

    @Test func diagonalCornerGapUsesExactEuclideanDistance() throws {
        // Corner distance = sqrt(3^2 + 4^2) = 5 exactly.
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 103, y1: 104, x2: 200, y2: 200),
        ])
        #expect(try r.selfSpaceViolations(minSpace: 5).isEmpty)
        #expect(try r.selfSpaceViolations(minSpace: 6).count == 1)
    }
}

// MARK: - Connectivity

@Suite("Region Connectivity")
struct RegionConnectivityTests {

    @Test func disjointPolygonsAreSeparateComponents() throws {
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 200, y1: 0, x2: 300, y2: 100),
        ])
        let components = r.connectedComponents()
        #expect(components.count == 2)
        #expect(components.allSatisfy { $0.area == 10000 })
    }

    @Test func edgeAbuttingPolygonsAreOneComponent() throws {
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 100, y1: 0, x2: 200, y2: 100),
        ])
        let components = r.connectedComponents()
        #expect(components.count == 1)
        #expect(components.first?.area == 20000)
    }

    @Test func cornerTouchingPolygonsAreSeparateComponents() throws {
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 100, y2: 100),
            makeBox(x1: 100, y1: 100, x2: 200, y2: 200),
        ])
        #expect(r.connectedComponents().count == 2)
    }

    @Test func mergedLShapeSpanningMultiplePolygonsIsOneComponent() throws {
        // After a boolean merge an L-shape becomes stacked rectangles in
        // separate polygons; component analysis must reunite them.
        let merged = try Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 200, y2: 100)])
            .union(Region(layer: 1, polygons: [makeBox(x1: 0, y1: 100, x2: 100, y2: 200)]))
        let components = merged.connectedComponents()
        #expect(components.count == 1)
        #expect(components.first?.area == 30000)
    }

    @Test func donutHasOneHole() throws {
        let outer = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 300, y2: 300)])
        let inner = Region(layer: 1, polygons: [makeBox(x1: 100, y1: 100, x2: 200, y2: 200)])
        let donut = try outer.subtracting(inner)
        let holes = try donut.holes()
        #expect(holes.count == 1)
        #expect(holes.first?.area == 10000)
    }

    @Test func solidRectangleHasNoHoles() throws {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        #expect(try r.holes().isEmpty)
    }

    @Test func containsIsBoundaryInclusive() throws {
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

    @Test func dilationDoesNotFillConcavities() throws {
        let l = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 200, y2: 100),
            makeBox(x1: 0, y1: 100, x2: 100, y2: 200),
        ])
        let dilated = try l.sized(by: 10)
        let expected = try Region(layer: 1, polygons: [makeBox(x1: -10, y1: -10, x2: 210, y2: 110)])
            .union(Region(layer: 1, polygons: [makeBox(x1: -10, y1: 90, x2: 110, y2: 210)]))
        #expect(try dilated.symmetricDifference(expected).isEmpty)
        #expect(dilated.area == 38400)
    }

    @Test func erosionIsExactSquareErosion() throws {
        let l = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 200, y2: 100),
            makeBox(x1: 0, y1: 100, x2: 100, y2: 200),
        ])
        let eroded = try l.sized(by: -20)
        let expected = try Region(layer: 1, polygons: [makeBox(x1: 20, y1: 20, x2: 180, y2: 80)])
            .union(Region(layer: 1, polygons: [makeBox(x1: 20, y1: 20, x2: 80, y2: 180)]))
        #expect(try eroded.symmetricDifference(expected).isEmpty)
        #expect(eroded.area == 15600)
    }

    @Test func openingRemovesNarrowArm() throws {
        // Wide base with a narrow arm: opening with radius 50 must remove
        // the 80-wide arm and keep the base intact.
        let shape = Region(layer: 1, polygons: [
            makeBox(x1: 0, y1: 0, x2: 400, y2: 200),
            makeBox(x1: 0, y1: 200, x2: 80, y2: 400),
        ])
        let opened = try shape.sized(by: -50).sized(by: 50)
        let expected = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 400, y2: 200)])
        #expect(try opened.symmetricDifference(expected).isEmpty)
        #expect(opened.area == 80000)
    }

    @Test func erosionThatConsumesEverythingIsEmpty() throws {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 30, y2: 30)])
        #expect(try r.sized(by: -20).isEmpty)
    }
}

// MARK: - Enclosure Robustness

@Suite("Region Enclosure Robustness")
struct RegionEnclosureRobustnessTests {

    @Test func innerCompletelyOutsideOuterIsViolation() throws {
        let outer = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let inner = Region(layer: 2, polygons: [makeBox(layer: 2, x1: 300, y1: 300, x2: 400, y2: 400)])
        let violations = try outer.enclosureViolations(inner: inner, minEnclosure: 10)
        #expect(!violations.isEmpty)
    }

    @Test func innerPartiallyOutsideOuterIsViolation() throws {
        let outer = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let inner = Region(layer: 2, polygons: [makeBox(layer: 2, x1: 50, y1: 50, x2: 150, y2: 150)])
        let violations = try outer.enclosureViolations(inner: inner, minEnclosure: 10)
        #expect(!violations.isEmpty)
    }

    @Test func wellEnclosedInnerPasses() throws {
        let outer = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let inner = Region(layer: 2, polygons: [makeBox(layer: 2, x1: 20, y1: 20, x2: 80, y2: 80)])
        #expect(try outer.enclosureViolations(inner: inner, minEnclosure: 20).isEmpty)
    }
}

// MARK: - Width on Union Coverage

@Suite("Region Width Union Coverage")
struct RegionWidthUnionCoverageTests {

    /// Two wide segments of one feature overlapping with a tiny vertical
    /// offset: the union's stacked-rectangle seam must not read as a
    /// sliver-thin band. Local coverage everywhere is at least 280.
    @Test func staircaseOverlapDoesNotFlagWidth() throws {
        let first = makeBox(x1: 20, y1: 3070, x2: 450, y2: 3350)
        let second = makeBox(x1: 400, y1: 3080, x2: 7760, y2: 3360)
        let merged = try Region(layer: 1, polygons: [first]).union(Region(layer: 1, polygons: [second]))
        #expect(try merged.widthViolations(minWidth: 280).isEmpty)
    }

    /// A genuinely narrow protrusion on top of wide metal must still flag:
    /// its left/right edges are true boundaries 100 apart.
    @Test func narrowProtrusionOnWideMetalFlagsWidth() throws {
        let base = makeBox(x1: 0, y1: 0, x2: 1000, y2: 500)
        let jog = makeBox(x1: 400, y1: 500, x2: 500, y2: 600)
        let merged = try Region(layer: 1, polygons: [base]).union(Region(layer: 1, polygons: [jog]))
        let violations = try merged.widthViolations(minWidth: 280)
        #expect(violations.count == 1)
        let xs = violations.flatMap { [$0.edge1.p1.x, $0.edge2.p1.x] }.sorted()
        #expect(xs == [400, 500])
    }

    /// Abutting (edge-sharing, non-overlapping) segments with an offset also
    /// form one feature whose seam must not flag.
    @Test func abuttingOffsetSegmentsDoNotFlagWidth() throws {
        let first = makeBox(x1: 0, y1: 0, x2: 500, y2: 300)
        let second = makeBox(x1: 500, y1: 10, x2: 1000, y2: 310)
        let merged = try Region(layer: 1, polygons: [first]).union(Region(layer: 1, polygons: [second]))
        #expect(try merged.widthViolations(minWidth: 280).isEmpty)
    }
}
