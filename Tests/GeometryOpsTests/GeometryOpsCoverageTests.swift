import Testing
import LayoutIR
@testable import GeometryOps

private func box(layer: Int16 = 1, x1: Int32, y1: Int32, x2: Int32, y2: Int32) -> IRBoundary {
    IRBoundary(layer: layer, datatype: 0, points: [
        IRPoint(x: x1, y: y1), IRPoint(x: x2, y: y1),
        IRPoint(x: x2, y: y2), IRPoint(x: x1, y: y2),
        IRPoint(x: x1, y: y1),
    ], properties: [])
}

// MARK: - XOR Partial Overlap

@Suite("XOR Partial Overlap")
struct XORPartialOverlapTests {

    @Test func xorPartialOverlapProducesTwoRegions() {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 50, y1: 0, x2: 150, y2: 100)])
        let result = a.xor(b)
        // XOR should produce area = 100*100 + 100*100 - 2*(50*100) = 10000
        #expect(result.area == 10000)
        #expect(!result.isEmpty)
    }

    @Test func xorNoOverlap() {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 200, y1: 0, x2: 300, y2: 100)])
        let result = a.xor(b)
        #expect(result.area == 20000) // Both regions preserved
    }
}

// MARK: - Y-Gap Spacing Violations

@Suite("Y-Gap Spacing")
struct YGapSpacingTests {

    @Test func verticalGapTooSmall() {
        // Two boxes stacked vertically with 20-unit gap
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 0, y1: 120, x2: 100, y2: 220)])
        let violations = a.spaceViolations(to: b, minSpace: 50)
        // gap = 20 < 50, X ranges overlap fully → violation
        #expect(violations.count == 1)
    }

    @Test func verticalGapSufficient() {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 0, y1: 200, x2: 100, y2: 300)])
        let violations = a.spaceViolations(to: b, minSpace: 50)
        // gap = 100 >= 50 → no violation
        #expect(violations.isEmpty)
    }

    @Test func verticalGapPartialXOverlap() {
        // Boxes overlap in X partially
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 50, y1: 110, x2: 150, y2: 210)])
        let violations = a.spaceViolations(to: b, minSpace: 50)
        // Y gap = 10 < 50, X overlap = 50..100 → violation
        #expect(violations.count == 1)
    }
}

// MARK: - BoundingBox Multi-Polygon

@Suite("BoundingBox Coverage")
struct BoundingBoxTests {

    @Test func multiPolygonBoundingBox() {
        let r = Region(layer: 1, polygons: [
            box(x1: -100, y1: -200, x2: 50, y2: 50),
            box(x1: 300, y1: 400, x2: 500, y2: 600),
        ])
        let bb = r.boundingBox
        #expect(bb?.minX == -100)
        #expect(bb?.minY == -200)
        #expect(bb?.maxX == 500)
        #expect(bb?.maxY == 600)
    }

    @Test func emptyRegionBoundingBox() {
        let r = Region(layer: 1)
        #expect(r.boundingBox == nil)
    }

    @Test func singlePolygonBoundingBox() {
        let r = Region(layer: 1, polygons: [box(x1: 10, y1: 20, x2: 30, y2: 40)])
        let bb = r.boundingBox
        #expect(bb?.minX == 10)
        #expect(bb?.minY == 20)
        #expect(bb?.maxX == 30)
        #expect(bb?.maxY == 40)
    }
}

// MARK: - NOT with partial overlap

@Suite("NOT Partial Overlap")
struct NOTPartialOverlapTests {

    @Test func notPartialSubtraction() {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 200, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 100, y1: 0, x2: 300, y2: 100)])
        let result = a.not(b)
        // a minus overlap = 0..100 x 0..100 = area 10000
        #expect(result.area == 10000)
    }

    @Test func notNoOverlap() {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 200, y1: 0, x2: 300, y2: 100)])
        let result = a.not(b)
        #expect(result.area == 10000) // Unchanged
    }
}

// MARK: - AND with partial overlap

@Suite("AND Partial Overlap")
struct ANDPartialOverlapTests {

    @Test func andPartialOverlap() {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 50, y1: 25, x2: 150, y2: 75)])
        let result = a.and(b)
        // Intersection: 50..100 x 25..75 = 50*50 = 2500
        #expect(result.area == 2500)
    }

    @Test func andNoOverlap() {
        let a = Region(layer: 1, polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [box(x1: 200, y1: 200, x2: 300, y2: 300)])
        let result = a.and(b)
        #expect(result.isEmpty)
    }
}
