import Testing
import LayoutIR
@testable import GeometryOps

// MARK: - Helper

private func box(layer: Int16 = 1, x1: Int32, y1: Int32, x2: Int32, y2: Int32) -> IRBoundary {
    IRBoundary(layer: layer, datatype: 0, points: [
        IRPoint(x: x1, y: y1), IRPoint(x: x2, y: y1),
        IRPoint(x: x2, y: y2), IRPoint(x: x1, y: y2),
        IRPoint(x: x1, y: y1),
    ], properties: [])
}

// MARK: - Region Edge Cases

@Suite("Region Edge Cases")
struct RegionEdgeCaseTests {

    @Test func singlePointPolygon() {
        // Degenerate: single point repeated
        let poly = IRBoundary(layer: 1, datatype: 0, points: [
            IRPoint(x: 50, y: 50), IRPoint(x: 50, y: 50),
        ], properties: [])
        let r = Region(layer: 1, polygons: [poly])
        #expect(r.area == 0)
        #expect(r.edgeCount == 1)
    }

    @Test func linePolygon() {
        // Degenerate: two distinct points forming a line
        let poly = IRBoundary(layer: 1, datatype: 0, points: [
            IRPoint(x: 0, y: 0), IRPoint(x: 100, y: 0), IRPoint(x: 0, y: 0),
        ], properties: [])
        let r = Region(layer: 1, polygons: [poly])
        #expect(r.area == 0)
    }

    @Test func veryThinRectangle() {
        let r = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 1, y2: 1000000)])
        #expect(r.area == 1000000)
    }

    @Test func multiplePolygonsArea() {
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

    @Test func orWithEmptyRegion() {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let empty = Region(layer: 1)
        let result = a.or(empty)
        #expect(result.area == 10000)
    }

    @Test func andWithEmptyRegion() {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let empty = Region(layer: 1)
        let result = a.and(empty)
        #expect(result.isEmpty)
    }

    @Test func xorOfIdenticalRegions() {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let result = a.xor(b)
        #expect(result.isEmpty)
    }

    @Test func notOfSameRegion() {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let result = a.not(b)
        #expect(result.isEmpty)
    }

    @Test func orOfIdenticalRegions() {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let result = a.or(b)
        #expect(result.area == 10000) // Same as original
    }

    @Test func andOfContainedRegion() {
        let outer = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 200, y2: 200)])
        let inner = Region(layer: 1, polygons: [box(x1: 50, y1: 50, x2: 150, y2: 150)])
        let result = outer.and(inner)
        #expect(result.area == 10000) // inner area
    }

    @Test func notRemovesContainedPortion() {
        let outer = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 200, y2: 200)])
        let inner = Region(layer: 1, polygons: [box(x1: 50, y1: 50, x2: 150, y2: 150)])
        let result = outer.not(inner)
        // 40000 - 10000 = 30000
        #expect(result.area == 30000)
    }

    @Test func touchingRectanglesOr() {
        // Two rectangles that share an edge
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 100, y1: 0, x2: 200, y2: 100)])
        let result = a.or(b)
        #expect(result.area == 20000)
    }

    @Test func threeWayBooleanChain() {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 50, y1: 0, x2: 150, y2: 100)])
        let c = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 150, y2: 50)])
        // (A OR B) AND C
        let result = a.or(b).and(c)
        // A OR B = 0..150 x 0..100, AND C = 0..150 x 0..50 = 7500
        #expect(result.area == 7500)
    }

    @Test func bothEmpty() {
        let a = Region(layer: 1)
        let b = Region(layer: 1)
        #expect(a.or(b).isEmpty)
        #expect(a.and(b).isEmpty)
        #expect(a.xor(b).isEmpty)
        #expect(a.not(b).isEmpty)
    }
}

// MARK: - Sizing Edge Cases

@Suite("Sizing Edge Cases")
struct SizingEdgeCaseTests {

    @Test func sizeByZero() {
        let r = Region(layer: 1, polygons: [box(x1: 10, y1: 10, x2: 90, y2: 90)])
        let result = r.sized(by: 0)
        #expect(result.area == r.area)
    }

    @Test func shrinkLargerThanHalfDimension() {
        // 100x100 box, shrink by 60 → -20..160 is invalid → vanishes
        let r = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let result = r.sized(by: -60)
        #expect(result.isEmpty)
    }

    @Test func shrinkAsymmetricRectangle() {
        // 200x50 rectangle, shrink by 20 → 160x10
        let r = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 200, y2: 50)])
        let result = r.sized(by: -20)
        #expect(result.area == 1600) // 160 * 10
    }

    @Test func growEmptyRegion() {
        let r = Region(layer: 1)
        let result = r.sized(by: 100)
        #expect(result.isEmpty)
    }

    @Test func growMultiplePolygons() {
        let r = Region(layer: 1, polygons: [
            box(x1: 0, y1: 0, x2: 50, y2: 50),
            box(x1: 200, y1: 0, x2: 250, y2: 50),
        ])
        let result = r.sized(by: 10)
        #expect(result.polygons.count == 2)
        // Each grows from 2500 to 4900 (70*70)
        #expect(result.area == 9800)
    }
}

// MARK: - DRC Edge Cases

@Suite("DRC Edge Cases")
struct DRCEdgeCaseTests {

    @Test func widthExactlyAtLimit() {
        let r = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 50, y2: 100)])
        let violations = r.widthViolations(minWidth: 50)
        #expect(violations.isEmpty) // 50 == 50, not a violation
    }

    @Test func widthOneUnderLimit() {
        let r = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 49, y2: 100)])
        let violations = r.widthViolations(minWidth: 50)
        #expect(violations.count == 1) // 49 < 50
    }

    @Test func widthBothDimensionsFail() {
        let r = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 30, y2: 40)])
        let violations = r.widthViolations(minWidth: 50)
        #expect(violations.count == 2) // Both 30 and 40 < 50
    }

    @Test func spaceExactlyAtLimit() {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 150, y1: 0, x2: 250, y2: 100)])
        let violations = a.spaceViolations(to: b, minSpace: 50)
        #expect(violations.isEmpty) // gap = 50 == 50
    }

    @Test func spaceTouchingRegions() {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 100, y1: 0, x2: 200, y2: 100)])
        let violations = a.spaceViolations(to: b, minSpace: 50)
        // gap = 0, not > 0, so no space violation reported for touching
        #expect(violations.isEmpty)
    }

    @Test func spaceNonOverlappingInY() {
        // Two boxes separated in X but non-overlapping in Y → no space violation
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 110, y1: 200, x2: 210, y2: 300)])
        let violations = a.spaceViolations(to: b, minSpace: 50)
        // They don't overlap in Y, so no face-to-face violation
        #expect(violations.isEmpty)
    }

    @Test func enclosureExactlyAtLimit() {
        let outer = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 200, y2: 200)])
        let inner = Region(layer: 2, polygons: [box(x1: 50, y1: 50, x2: 150, y2: 150)])
        let violations = outer.enclosureViolations(inner: inner, minEnclosure: 50)
        #expect(violations.isEmpty) // all sides == 50
    }

    @Test func enclosureOneSideFails() {
        let outer = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 200, y2: 200)])
        let inner = Region(layer: 2, polygons: [box(x1: 30, y1: 50, x2: 150, y2: 150)])
        let violations = outer.enclosureViolations(inner: inner, minEnclosure: 50)
        // Only left side fails (30 < 50)
        #expect(violations.count == 1)
    }

    @Test func enclosureAllSidesFail() {
        let outer = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 200, y2: 200)])
        let inner = Region(layer: 2, polygons: [box(x1: 10, y1: 20, x2: 195, y2: 185)])
        let violations = outer.enclosureViolations(inner: inner, minEnclosure: 50)
        // left=10, bottom=20, right=5, top=15 → all 4 fail
        #expect(violations.count == 4)
    }

    @Test func enclosureInnerNotContained() {
        // Inner extends beyond outer → no enclosure check
        let outer = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let inner = Region(layer: 2, polygons: [box(x1: 50, y1: 50, x2: 200, y2: 200)])
        let violations = outer.enclosureViolations(inner: inner, minEnclosure: 10)
        #expect(violations.isEmpty) // Not contained, so no check
    }

    @Test func multiplePolygonsDRC() {
        let r = Region(layer: 1, polygons: [
            box(x1: 0, y1: 0, x2: 30, y2: 100),    // width 30 → fail
            box(x1: 200, y1: 0, x2: 300, y2: 100),  // width 100 → pass
            box(x1: 400, y1: 0, x2: 420, y2: 100),  // width 20 → fail
        ])
        let violations = r.widthViolations(minWidth: 50)
        #expect(violations.count == 2) // Two polygons fail
    }

    @Test func spaceMultiplePairs() {
        let a = Region(layer: 1, polygons: [
            box(x1: 0, y1: 0, x2: 100, y2: 100),
            box(x1: 0, y1: 200, x2: 100, y2: 300),
        ])
        let b = Region(layer: 1, polygons: [
            box(x1: 120, y1: 0, x2: 200, y2: 100),   // gap = 20, Y overlaps with a[0]
            box(x1: 120, y1: 200, x2: 200, y2: 300),  // gap = 20, Y overlaps with a[1]
        ])
        let violations = a.spaceViolations(to: b, minSpace: 50)
        #expect(violations.count == 2)
    }
}
