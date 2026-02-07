import Testing
@testable import LayoutIR

@Suite("IRPoint")
struct IRPointTests {
    @Test func zero() {
        let p = IRPoint.zero
        #expect(p.x == 0)
        #expect(p.y == 0)
    }

    @Test func equality() {
        let a = IRPoint(x: 100, y: -200)
        let b = IRPoint(x: 100, y: -200)
        #expect(a == b)
    }

    @Test func inequality() {
        let a = IRPoint(x: 1, y: 2)
        let b = IRPoint(x: 1, y: 3)
        #expect(a != b)
    }
}

@Suite("IRUnits")
struct IRUnitsTests {
    @Test func defaultUnits() {
        let u = IRUnits.default
        #expect(u.dbuPerMicron == 1000)
    }

    @Test func customUnits() {
        let u = IRUnits(dbuPerMicron: 100)
        #expect(u.dbuPerMicron == 100)
    }

    @Test func metersPerDBU() {
        let u = IRUnits(dbuPerMicron: 1000)
        #expect(abs(u.metersPerDBU - 1e-9) < 1e-20)
    }
}

@Suite("IRPathType")
struct IRPathTypeTests {
    @Test func allCases() {
        #expect(IRPathType.flush.rawValue == 0)
        #expect(IRPathType.round.rawValue == 1)
        #expect(IRPathType.halfWidthExtend.rawValue == 2)
    }
}

@Suite("IRTransform")
struct IRTransformTests {
    @Test func identity() {
        let t = IRTransform.identity
        #expect(t.mirrorX == false)
        #expect(t.magnification == 1.0)
        #expect(t.angle == 0.0)
    }

    @Test func customTransform() {
        let t = IRTransform(mirrorX: true, magnification: 2.0, angle: 90.0)
        #expect(t.mirrorX == true)
        #expect(t.magnification == 2.0)
        #expect(t.angle == 90.0)
    }
}

@Suite("IRProperty")
struct IRPropertyTests {
    @Test func construction() {
        let p = IRProperty(attribute: 1, value: "test")
        #expect(p.attribute == 1)
        #expect(p.value == "test")
    }
}

@Suite("IRBoundary")
struct IRBoundaryTests {
    @Test func rectangle() {
        let points: [IRPoint] = [
            IRPoint(x: 0, y: 0),
            IRPoint(x: 100, y: 0),
            IRPoint(x: 100, y: 50),
            IRPoint(x: 0, y: 50),
            IRPoint(x: 0, y: 0),
        ]
        let b = IRBoundary(layer: 1, datatype: 0, points: points)
        #expect(b.layer == 1)
        #expect(b.datatype == 0)
        #expect(b.points.count == 5)
        #expect(b.points.first == b.points.last)
    }

    @Test func properties() {
        let b = IRBoundary(
            layer: 10,
            datatype: 0,
            points: [IRPoint(x: 0, y: 0), IRPoint(x: 1, y: 0), IRPoint(x: 1, y: 1), IRPoint(x: 0, y: 0)],
            properties: [IRProperty(attribute: 1, value: "net_name")]
        )
        #expect(b.properties.count == 1)
    }
}

@Suite("IRPath")
struct IRPathTests {
    @Test func construction() {
        let p = IRPath(
            layer: 1,
            datatype: 0,
            pathType: .halfWidthExtend,
            width: 230,
            points: [IRPoint(x: 0, y: 0), IRPoint(x: 1000, y: 0)]
        )
        #expect(p.width == 230)
        #expect(p.pathType == .halfWidthExtend)
        #expect(p.points.count == 2)
    }
}

@Suite("IRCellRef")
struct IRCellRefTests {
    @Test func construction() {
        let r = IRCellRef(
            cellName: "INV",
            origin: IRPoint(x: 500, y: 1000),
            transform: .identity
        )
        #expect(r.cellName == "INV")
        #expect(r.origin.x == 500)
    }

    @Test func withTransform() {
        let r = IRCellRef(
            cellName: "NAND",
            origin: .zero,
            transform: IRTransform(mirrorX: true, magnification: 1.0, angle: 180.0)
        )
        #expect(r.transform.mirrorX == true)
        #expect(r.transform.angle == 180.0)
    }
}

@Suite("IRArrayRef")
struct IRArrayRefTests {
    @Test func construction() {
        let a = IRArrayRef(
            cellName: "VIA",
            transform: .identity,
            columns: 4,
            rows: 2,
            referencePoints: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 400, y: 0),
                IRPoint(x: 0, y: 200),
            ]
        )
        #expect(a.columns == 4)
        #expect(a.rows == 2)
        #expect(a.referencePoints.count == 3)
    }
}

@Suite("IRText")
struct IRTextTests {
    @Test func construction() {
        let t = IRText(
            layer: 1,
            texttype: 0,
            position: IRPoint(x: 500, y: 250),
            string: "VDD"
        )
        #expect(t.string == "VDD")
        #expect(t.layer == 1)
    }
}

@Suite("IRElement")
struct IRElementTests {
    @Test func boundaryElement() {
        let b = IRBoundary(
            layer: 1,
            datatype: 0,
            points: [IRPoint(x: 0, y: 0), IRPoint(x: 1, y: 0), IRPoint(x: 1, y: 1), IRPoint(x: 0, y: 0)]
        )
        let e = IRElement.boundary(b)
        if case .boundary(let inner) = e {
            #expect(inner.layer == 1)
        } else {
            Issue.record("Expected boundary element")
        }
    }
}

@Suite("IRCell")
struct IRCellTests {
    @Test func emptyCell() {
        let c = IRCell(name: "TOP")
        #expect(c.name == "TOP")
        #expect(c.elements.isEmpty)
    }

    @Test func cellWithElements() {
        let boundary = IRBoundary(
            layer: 1,
            datatype: 0,
            points: [IRPoint(x: 0, y: 0), IRPoint(x: 100, y: 0), IRPoint(x: 100, y: 100), IRPoint(x: 0, y: 100), IRPoint(x: 0, y: 0)]
        )
        let c = IRCell(name: "RECT", elements: [.boundary(boundary)])
        #expect(c.elements.count == 1)
    }
}

@Suite("IRLibrary")
struct IRLibraryTests {
    @Test func emptyLibrary() {
        let lib = IRLibrary(name: "TEST_LIB", units: .default)
        #expect(lib.name == "TEST_LIB")
        #expect(lib.cells.isEmpty)
    }

    @Test func cellLookup() {
        let cell = IRCell(name: "NAND2")
        let lib = IRLibrary(name: "LIB", units: .default, cells: [cell])
        #expect(lib.cell(named: "NAND2") != nil)
        #expect(lib.cell(named: "INV") == nil)
    }

    @Test func multipleCells() {
        let a = IRCell(name: "A")
        let b = IRCell(name: "B")
        let lib = IRLibrary(name: "LIB", units: .default, cells: [a, b])
        #expect(lib.cells.count == 2)
    }
}
