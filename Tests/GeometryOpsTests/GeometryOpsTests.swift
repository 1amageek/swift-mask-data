import Testing
import LayoutIR
@testable import GeometryOps

// MARK: - Helpers

func makeBox(layer: Int16 = 1, x1: Int32, y1: Int32, x2: Int32, y2: Int32) -> IRBoundary {
    IRBoundary(layer: layer, datatype: 0, points: [
        IRPoint(x: x1, y: y1), IRPoint(x: x2, y: y1),
        IRPoint(x: x2, y: y2), IRPoint(x: x1, y: y2),
        IRPoint(x: x1, y: y1),
    ], properties: [])
}

// MARK: - Region Basics

@Suite("Region Basics")
struct RegionBasicsTests {

    @Test func emptyRegion() {
        let r = Region(layer: 1)
        #expect(r.isEmpty)
        #expect(r.area == 0)
        #expect(r.edgeCount == 0)
        #expect(r.boundingBox == nil)
    }

    @Test func singleBox() {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 200)])
        #expect(!r.isEmpty)
        #expect(r.area == 20000) // 100 * 200
        #expect(r.edgeCount == 4)
    }

    @Test func boundingBox() {
        let r = Region(layer: 1, polygons: [
            makeBox(x1: 10, y1: 20, x2: 50, y2: 60),
            makeBox(x1: 30, y1: 40, x2: 80, y2: 90),
        ])
        let bb = r.boundingBox!
        #expect(bb.minX == 10)
        #expect(bb.minY == 20)
        #expect(bb.maxX == 80)
        #expect(bb.maxY == 90)
    }
}

// MARK: - Boolean Operations

@Suite("Region Boolean")
struct RegionBooleanTests {

    @Test func orNonOverlapping() {
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 200, y1: 0, x2: 300, y2: 100)])
        let result = a.or(b)
        #expect(result.polygons.count == 2)
        #expect(result.area == 20000)
    }

    @Test func orOverlapping() {
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 50, y1: 0, x2: 150, y2: 100)])
        let result = a.or(b)
        // Should produce a single merged rectangle 0..150 x 0..100
        #expect(result.area == 15000)
    }

    @Test func andOverlapping() {
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 50, y1: 0, x2: 150, y2: 100)])
        let result = a.and(b)
        // Intersection: 50..100 x 0..100 = area 5000
        #expect(result.area == 5000)
    }

    @Test func andNonOverlapping() {
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 200, y1: 0, x2: 300, y2: 100)])
        let result = a.and(b)
        #expect(result.isEmpty)
    }

    @Test func xorOperation() {
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 50, y1: 0, x2: 150, y2: 100)])
        let result = a.xor(b)
        // XOR = OR - AND = 15000 - 5000 = 10000
        #expect(result.area == 10000)
    }

    @Test func notOperation() {
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 50, y1: 0, x2: 150, y2: 100)])
        let result = a.not(b)
        // A - B = 0..50 x 0..100 = area 5000
        #expect(result.area == 5000)
    }
}

// MARK: - Sizing

@Suite("Region Sizing")
struct RegionSizingTests {

    @Test func grow() {
        let r = Region(layer: 1, polygons: [makeBox(x1: 10, y1: 10, x2: 90, y2: 90)])
        let grown = r.sized(by: 10)
        #expect(grown.area == 10000) // 100*100
    }

    @Test func shrink() {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let shrunk = r.sized(by: -20)
        // 60*60 = 3600
        #expect(shrunk.area == 3600)
    }

    @Test func shrinkToNothing() {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 40, y2: 40)])
        let shrunk = r.sized(by: -30)
        // 40 - 60 < 0, polygon should vanish
        #expect(shrunk.isEmpty)
    }
}

// MARK: - DRC

@Suite("DRC Checks")
struct DRCCheckTests {

    @Test func widthPass() {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let violations = r.widthViolations(minWidth: 50)
        #expect(violations.isEmpty)
    }

    @Test func widthFail() {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 30, y2: 100)])
        let violations = r.widthViolations(minWidth: 50)
        #expect(!violations.isEmpty) // Width 30 < 50
    }

    @Test func spacePass() {
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 200, y1: 0, x2: 300, y2: 100)])
        let violations = a.spaceViolations(to: b, minSpace: 50)
        #expect(violations.isEmpty) // gap = 100 >= 50
    }

    @Test func spaceFail() {
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 120, y1: 0, x2: 220, y2: 100)])
        let violations = a.spaceViolations(to: b, minSpace: 50)
        #expect(!violations.isEmpty) // gap = 20 < 50
    }

    @Test func enclosurePass() {
        let outer = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 200, y2: 200)])
        let inner = Region(layer: 2, polygons: [makeBox(x1: 50, y1: 50, x2: 150, y2: 150)])
        let violations = outer.enclosureViolations(inner: inner, minEnclosure: 50)
        #expect(violations.isEmpty)
    }

    @Test func enclosureFail() {
        let outer = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 200, y2: 200)])
        let inner = Region(layer: 2, polygons: [makeBox(x1: 10, y1: 50, x2: 150, y2: 150)])
        let violations = outer.enclosureViolations(inner: inner, minEnclosure: 50)
        #expect(!violations.isEmpty) // left enclosure = 10 < 50
    }
}
