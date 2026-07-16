import Testing
import LayoutIR
@testable import MaskGeometry

// MARK: - Helper

private func box(layer: Int16 = 1, x1: Int32, y1: Int32, x2: Int32, y2: Int32) -> IRBoundary {
    IRBoundary(layer: layer, datatype: 0, points: [
        IRPoint(x: x1, y: y1), IRPoint(x: x2, y: y1),
        IRPoint(x: x2, y: y2), IRPoint(x: x1, y: y2),
        IRPoint(x: x1, y: y1),
    ], properties: [])
}

private func lShape(layer: Int16 = 1) -> IRBoundary {
    IRBoundary(layer: layer, datatype: 0, points: [
        IRPoint(x: 0, y: 0),
        IRPoint(x: 100, y: 0),
        IRPoint(x: 100, y: 40),
        IRPoint(x: 40, y: 40),
        IRPoint(x: 40, y: 100),
        IRPoint(x: 0, y: 100),
        IRPoint(x: 0, y: 0),
    ], properties: [])
}

private func boxWithCollinearVertex(layer: Int16 = 1) -> IRBoundary {
    IRBoundary(layer: layer, datatype: 0, points: [
        IRPoint(x: 0, y: 0),
        IRPoint(x: 100, y: 0),
        IRPoint(x: 100, y: 10),
        IRPoint(x: 100, y: 100),
        IRPoint(x: 0, y: 100),
        IRPoint(x: 0, y: 0),
    ], properties: [])
}

@Suite("Scanline Sweep Invariants")
struct ScanlineSweepInvariantTests {
    @Test func invalidBandThrowsInsteadOfBeingDropped() throws {
        let invalidBands = [
            RegionBoolean.Band(xMin: 10, xMax: 10, yMin: 0, yMax: 20),
        ]

        #expect(throws: ScanlineSweep.SweepError.invalidBand(
            input: "a",
            index: 0,
            xMin: 10,
            xMax: 10,
            yMin: 0,
            yMax: 20
        )) {
            try ScanlineSweep.checkedSweepRows(invalidBands, []) { _, _, _, _ in
                Issue.record("Invalid bands must be rejected before sweeping")
            }
        }
    }
}

// MARK: - Region Edge Cases

@Suite("Region Edge Cases")
struct RegionEdgeCaseTests {

    @Test func singlePointPolygon() throws {
        // Degenerate: single point repeated
        let poly = IRBoundary(layer: 1, datatype: 0, points: [
            IRPoint(x: 50, y: 50), IRPoint(x: 50, y: 50),
        ], properties: [])
        let r = Region(layer: 1, polygons: [poly])
        #expect(r.area == 0)
        #expect(r.edgeCount == 1)
    }

    @Test func linePolygon() throws {
        // Degenerate: two distinct points forming a line
        let poly = IRBoundary(layer: 1, datatype: 0, points: [
            IRPoint(x: 0, y: 0), IRPoint(x: 100, y: 0), IRPoint(x: 0, y: 0),
        ], properties: [])
        let r = Region(layer: 1, polygons: [poly])
        #expect(r.area == 0)
    }

    @Test func veryThinRectangle() throws {
        let r = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 1, y2: 1000000)])
        #expect(r.area == 1000000)
    }

    @Test func multiplePolygonsArea() throws {
        let r = Region(layer: 1, polygons: [
            box(x1: 0, y1: 0, x2: 100, y2: 100),
            box(x1: 200, y1: 0, x2: 400, y2: 100),
        ])
        #expect(r.area == 30000) // 10000 + 20000
    }
}

// MARK: - Boolean Edge Cases

@Suite("Boolean Edge Cases")
struct BooleanEdgeCaseTests {

    @Test func orWithEmptyRegion() throws {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let empty = Region(layer: 1)
        let result = try a.union(empty)
        #expect(result.area == 10000)
    }

    @Test func andWithEmptyRegion() throws {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let empty = Region(layer: 1)
        let result = try a.intersection(empty)
        #expect(result.isEmpty)
    }

    @Test func xorOfIdenticalRegions() throws {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let result = try a.symmetricDifference(b)
        #expect(result.isEmpty)
    }

    @Test func notOfSameRegion() throws {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let result = try a.subtracting(b)
        #expect(result.isEmpty)
    }

    @Test func orOfIdenticalRegions() throws {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let result = try a.union(b)
        #expect(result.area == 10000) // Same as original
    }

    @Test func andOfContainedRegion() throws {
        let outer = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 200, y2: 200)])
        let inner = Region(layer: 1, polygons: [box(x1: 50, y1: 50, x2: 150, y2: 150)])
        let result = try outer.intersection(inner)
        #expect(result.area == 10000) // inner area
    }

    @Test func notRemovesContainedPortion() throws {
        let outer = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 200, y2: 200)])
        let inner = Region(layer: 1, polygons: [box(x1: 50, y1: 50, x2: 150, y2: 150)])
        let result = try outer.subtracting(inner)
        // 40000 - 10000 = 30000
        #expect(result.area == 30000)
    }

    @Test func orPreservesConcaveManhattanArea() throws {
        let region = Region(layer: 1, polygons: [lShape()])
        let result = try region.union(Region(layer: 1))
        #expect(result.area == 6400)
    }

    @Test func andDoesNotFillConcaveManhattanInterior() throws {
        let region = Region(layer: 1, polygons: [lShape()])
        let missingCorner = Region(layer: 1, polygons: [box(x1: 60, y1: 60, x2: 90, y2: 90)])
        let result = try region.intersection(missingCorner)
        #expect(result.isEmpty)
    }

    @Test func notRemovesConcaveManhattanPortion() throws {
        let region = Region(layer: 1, polygons: [lShape()])
        let lowerLeft = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 40, y2: 40)])
        let result = try region.subtracting(lowerLeft)
        #expect(result.area == 4800)
    }

    @Test func touchingRectanglesOr() throws {
        // Two rectangles that share an edge
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 100, y1: 0, x2: 200, y2: 100)])
        let result = try a.union(b)
        #expect(result.area == 20000)
    }

    @Test func threeWayBooleanChain() throws {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 50, y1: 0, x2: 150, y2: 100)])
        let c = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 150, y2: 50)])
        // (A OR B) AND C
        let result = try a.union(b).intersection(c)
        // A OR B = 0..150 x 0..100, AND C = 0..150 x 0..50 = 7500
        #expect(result.area == 7500)
    }

    @Test func bothEmpty() throws {
        let a = Region(layer: 1)
        let b = Region(layer: 1)
        #expect(try a.union(b).isEmpty)
        #expect(try a.intersection(b).isEmpty)
        #expect(try a.symmetricDifference(b).isEmpty)
        #expect(try a.subtracting(b).isEmpty)
    }
}

// MARK: - Sizing Edge Cases

@Suite("Sizing Edge Cases")
struct SizingEdgeCaseTests {

    @Test func sizeByZero() throws {
        let r = Region(layer: 1, polygons: [box(x1: 10, y1: 10, x2: 90, y2: 90)])
        let result = try r.sized(by: 0)
        #expect(result.area == r.area)
    }

    @Test func shrinkLargerThanHalfDimension() throws {
        // 100x100 box, shrink by 60 → -20..160 is invalid → vanishes
        let r = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let result = try r.sized(by: -60)
        #expect(result.isEmpty)
    }

    @Test func shrinkAsymmetricRectangle() throws {
        // 200x50 rectangle, shrink by 20 → 160x10
        let r = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 200, y2: 50)])
        let result = try r.sized(by: -20)
        #expect(result.area == 1600) // 160 * 10
    }

    @Test func growEmptyRegion() throws {
        let r = Region(layer: 1)
        let result = try r.sized(by: 100)
        #expect(result.isEmpty)
    }

    @Test func growMultiplePolygons() throws {
        let r = Region(layer: 1, polygons: [
            box(x1: 0, y1: 0, x2: 50, y2: 50),
            box(x1: 200, y1: 0, x2: 250, y2: 50),
        ])
        let result = try r.sized(by: 10)
        #expect(result.polygons.count == 2)
        // Each grows from 2500 to 4900 (70*70)
        #expect(result.area == 9800)
    }
}

// MARK: - DRC Edge Cases

@Suite("DRC Edge Cases")
struct DRCEdgeCaseTests {

    @Test func widthExactlyAtLimit() throws {
        let r = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 50, y2: 100)])
        let violations = try r.widthViolations(minWidth: 50)
        #expect(violations.isEmpty) // 50 == 50, not a violation
    }

    @Test func widthOneUnderLimit() throws {
        let r = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 49, y2: 100)])
        let violations = try r.widthViolations(minWidth: 50)
        #expect(violations.count == 1) // 49 < 50
    }

    @Test func widthBothDimensionsFail() throws {
        let r = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 30, y2: 40)])
        let violations = try r.widthViolations(minWidth: 50)
        #expect(violations.count == 2) // Both 30 and 40 < 50
    }

    @Test func widthDetectsConcaveManhattanNeck() throws {
        let r = Region(layer: 1, polygons: [lShape()])
        let violations = try r.widthViolations(minWidth: 50)
        #expect(violations.count == 2)
    }

    @Test func widthIgnoresCollinearVertexBandSplits() throws {
        let r = Region(layer: 1, polygons: [boxWithCollinearVertex()])
        let violations = try r.widthViolations(minWidth: 50)
        #expect(violations.isEmpty)
    }

    @Test func spaceExactlyAtLimit() throws {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 150, y1: 0, x2: 250, y2: 100)])
        let violations = try a.spaceViolations(to: b, minSpace: 50)
        #expect(violations.isEmpty) // gap = 50 == 50
    }

    @Test func spaceTouchingRegions() throws {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 100, y1: 0, x2: 200, y2: 100)])
        let violations = try a.spaceViolations(to: b, minSpace: 50)
        // gap = 0, not > 0, so no space violation reported for touching
        #expect(violations.isEmpty)
    }

    @Test func spaceNonOverlappingInY() throws {
        // Two boxes separated in X but non-overlapping in Y → no space violation
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 110, y1: 200, x2: 210, y2: 300)])
        let violations = try a.spaceViolations(to: b, minSpace: 50)
        // They don't overlap in Y, so no face-to-face violation
        #expect(violations.isEmpty)
    }

    @Test func spaceDetectsConcaveManhattanInteriorGap() throws {
        let a = Region(layer: 1, polygons: [lShape()])
        let b = Region(layer: 1, polygons: [box(x1: 60, y1: 60, x2: 90, y2: 90)])
        let violations = try a.spaceViolations(to: b, minSpace: 50)
        #expect(violations.count == 2)
    }

    @Test func enclosureExactlyAtLimit() throws {
        let outer = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 200, y2: 200)])
        let inner = Region(layer: 2, polygons: [box(x1: 50, y1: 50, x2: 150, y2: 150)])
        let violations = try outer.enclosureViolations(inner: inner, minEnclosure: 50)
        #expect(violations.isEmpty) // all sides == 50
    }

    @Test func enclosureOneSideFails() throws {
        let outer = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 200, y2: 200)])
        let inner = Region(layer: 2, polygons: [box(x1: 30, y1: 50, x2: 150, y2: 150)])
        let violations = try outer.enclosureViolations(inner: inner, minEnclosure: 50)
        // Only left side fails (30 < 50)
        #expect(violations.count == 1)
    }

    @Test func enclosureAllSidesFail() throws {
        let outer = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 200, y2: 200)])
        let inner = Region(layer: 2, polygons: [box(x1: 10, y1: 20, x2: 195, y2: 185)])
        let violations = try outer.enclosureViolations(inner: inner, minEnclosure: 50)
        // left=10, bottom=20, right=5, top=15 → all 4 fail
        #expect(violations.count == 4)
    }

    @Test func enclosureInnerNotContained() throws {
        // Inner extends beyond outer → the uncovered part is a violation,
        // never a silent pass.
        let outer = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let inner = Region(layer: 2, polygons: [box(x1: 50, y1: 50, x2: 200, y2: 200)])
        let violations = try outer.enclosureViolations(inner: inner, minEnclosure: 10)
        #expect(!violations.isEmpty)
    }

    @Test func enclosureDoesNotTreatConcaveBBoxAsContainment() throws {
        // Inner sits in the concave notch of the L: inside the outer's
        // bounding box but outside its actual geometry → must be reported
        // as uncovered, not measured against the bounding box.
        let outer = Region(layer: 1, polygons: [lShape()])
        let inner = Region(layer: 2, polygons: [box(x1: 60, y1: 60, x2: 90, y2: 90)])
        let violations = try outer.enclosureViolations(inner: inner, minEnclosure: 10)
        #expect(violations.count == 1)
        let bb = violations.first
        #expect(bb?.edge1.p1.x == 60)
        #expect(bb?.edge2.p1.x == 90)
    }

    @Test func multiplePolygonsDRC() throws {
        let r = Region(layer: 1, polygons: [
            box(x1: 0, y1: 0, x2: 30, y2: 100),    // width 30 → fail
            box(x1: 200, y1: 0, x2: 300, y2: 100),  // width 100 → pass
            box(x1: 400, y1: 0, x2: 420, y2: 100),  // width 20 → fail
        ])
        let violations = try r.widthViolations(minWidth: 50)
        #expect(violations.count == 2) // Two polygons fail
    }

    @Test func spaceMultiplePairs() throws {
        let a = Region(layer: 1, polygons: [
            box(x1: 0, y1: 0, x2: 100, y2: 100),
            box(x1: 0, y1: 200, x2: 100, y2: 300),
        ])
        let b = Region(layer: 1, polygons: [
            box(x1: 120, y1: 0, x2: 200, y2: 100),   // gap = 20, Y overlaps with a[0]
            box(x1: 120, y1: 200, x2: 200, y2: 300),  // gap = 20, Y overlaps with a[1]
        ])
        let violations = try a.spaceViolations(to: b, minSpace: 50)
        #expect(violations.count == 2)
    }
}
