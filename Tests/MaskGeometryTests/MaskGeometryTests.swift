import Testing
import LayoutIR
@testable import MaskGeometry

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

    @Test func emptyRegion() throws {
        let r = Region(layer: 1)
        #expect(r.isEmpty)
        #expect(r.area == 0)
        #expect(r.edgeCount == 0)
        #expect(r.boundingBox == nil)
    }

    @Test func singleBox() throws {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 200)])
        #expect(!r.isEmpty)
        #expect(r.area == 20000) // 100 * 200
        #expect(r.edgeCount == 4)
    }

    @Test func boundingBox() throws {
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

    @Test func orNonOverlapping() throws {
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 200, y1: 0, x2: 300, y2: 100)])
        let result = try a.union(b)
        #expect(result.polygons.count == 2)
        #expect(result.area == 20000)
    }

    @Test func orOverlapping() throws {
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 50, y1: 0, x2: 150, y2: 100)])
        let result = try a.union(b)
        // Should produce a single merged rectangle 0..150 x 0..100
        #expect(result.area == 15000)
    }

    @Test func andOverlapping() throws {
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 50, y1: 0, x2: 150, y2: 100)])
        let result = try a.intersection(b)
        // Intersection: 50..100 x 0..100 = area 5000
        #expect(result.area == 5000)
    }

    @Test func andNonOverlapping() throws {
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 200, y1: 0, x2: 300, y2: 100)])
        let result = try a.intersection(b)
        #expect(result.isEmpty)
    }

    @Test func xorOperation() throws {
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 50, y1: 0, x2: 150, y2: 100)])
        let result = try a.symmetricDifference(b)
        // XOR = OR - AND = 15000 - 5000 = 10000
        #expect(result.area == 10000)
    }

    @Test func notOperation() throws {
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 50, y1: 0, x2: 150, y2: 100)])
        let result = try a.subtracting(b)
        // A - B = 0..50 x 0..100 = area 5000
        #expect(result.area == 5000)
    }
}

// MARK: - Sizing

@Suite("Region Sizing")
struct RegionSizingTests {

    @Test func grow() throws {
        let r = Region(layer: 1, polygons: [makeBox(x1: 10, y1: 10, x2: 90, y2: 90)])
        let grown = try r.sized(by: 10)
        #expect(grown.area == 10000) // 100*100
    }

    @Test func shrink() throws {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let shrunk = try r.sized(by: -20)
        // 60*60 = 3600
        #expect(shrunk.area == 3600)
    }

    @Test func shrinkToNothing() throws {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 40, y2: 40)])
        let shrunk = try r.sized(by: -30)
        // 40 - 60 < 0, polygon should vanish
        #expect(shrunk.isEmpty)
    }
}

// MARK: - DRC

@Suite("DRC Checks")
struct DRCCheckTests {

    @Test func widthPass() throws {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let violations = try r.widthViolations(minWidth: 50)
        #expect(violations.isEmpty)
    }

    @Test func widthFail() throws {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 30, y2: 100)])
        let violations = try r.widthViolations(minWidth: 50)
        #expect(!violations.isEmpty) // Width 30 < 50
    }

    @Test func spacePass() throws {
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 200, y1: 0, x2: 300, y2: 100)])
        let violations = try a.spaceViolations(to: b, minSpace: 50)
        #expect(violations.isEmpty) // gap = 100 >= 50
    }

    @Test func spaceFail() throws {
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 120, y1: 0, x2: 220, y2: 100)])
        let violations = try a.spaceViolations(to: b, minSpace: 50)
        #expect(!violations.isEmpty) // gap = 20 < 50
    }

    @Test func enclosurePass() throws {
        let outer = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 200, y2: 200)])
        let inner = Region(layer: 2, polygons: [makeBox(x1: 50, y1: 50, x2: 150, y2: 150)])
        let violations = try outer.enclosureViolations(inner: inner, minEnclosure: 50)
        #expect(violations.isEmpty)
    }

    @Test func enclosureFail() throws {
        let outer = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 200, y2: 200)])
        let inner = Region(layer: 2, polygons: [makeBox(x1: 10, y1: 50, x2: 150, y2: 150)])
        let violations = try outer.enclosureViolations(inner: inner, minEnclosure: 50)
        #expect(!violations.isEmpty) // left enclosure = 10 < 50
    }
}
