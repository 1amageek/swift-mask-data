import Testing
import Foundation
import LayoutIR
@testable import OASIS

/// Regression tests for OASIS round-trip bug fixes (round 2).
@Suite("OASIS Round-Trip Bug Fixes")
struct OASISRoundTripBugTests {

    // MARK: - Bug 1: Negative layer/datatype must not crash

    @Test func testNegativeLayerDoesNotCrash() throws {
        let boundary = IRBoundary(
            layer: -1,
            datatype: -5,
            points: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 100, y: 0),
                IRPoint(x: 100, y: 100),
                IRPoint(x: 0, y: 100),
                IRPoint(x: 0, y: 0),
            ],
            properties: []
        )
        let lib = IRLibrary(
            name: "NEGLAYER",
            units: .default,
            cells: [IRCell(name: "NEG", elements: [.boundary(boundary)])]
        )
        // Must not crash -- negative values are clamped to 0
        let data = try OASISLibraryWriter.write(lib)
        let result = try OASISLibraryReader.read(data)

        #expect(result.cells.count == 1)
        if case .boundary(let b) = result.cells[0].elements[0] {
            #expect(b.layer == 0)
            #expect(b.datatype == 0)
        } else {
            Issue.record("Expected boundary element")
        }
    }

    // MARK: - Bug 2: Property round-trip

    @Test func testPropertyRoundTrip() throws {
        let boundary = IRBoundary(
            layer: 1,
            datatype: 0,
            points: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 200, y: 0),
                IRPoint(x: 200, y: 200),
                IRPoint(x: 0, y: 200),
                IRPoint(x: 0, y: 0),
            ],
            properties: [
                IRProperty(attribute: 0, value: "net_name=VDD"),
                IRProperty(attribute: 0, value: "purpose=drawing"),
            ]
        )
        let lib = IRLibrary(
            name: "PROPTEST",
            units: .default,
            cells: [IRCell(name: "P", elements: [.boundary(boundary)])]
        )
        let data = try OASISLibraryWriter.write(lib)
        let result = try OASISLibraryReader.read(data)

        #expect(result.cells.count == 1)
        if case .boundary(let b) = result.cells[0].elements[0] {
            #expect(b.properties.count == 2)
            #expect(b.properties[0].value.contains("net_name"))
            #expect(b.properties[0].value.contains("VDD"))
            #expect(b.properties[1].value.contains("purpose"))
            #expect(b.properties[1].value.contains("drawing"))
        } else {
            Issue.record("Expected boundary element with properties")
        }
    }

    // MARK: - Bug 3: PATH extension scheme halfWidth round-trip

    @Test func testPathExtensionSchemeHalfWidth() throws {
        let path = IRPath(
            layer: 2,
            datatype: 0,
            pathType: .halfWidthExtend,
            width: 100,
            points: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 1000, y: 0),
            ],
            properties: []
        )
        let lib = IRLibrary(
            name: "PATHEXT",
            units: .default,
            cells: [IRCell(name: "W", elements: [.path(path)])]
        )
        let data = try OASISLibraryWriter.write(lib)
        let result = try OASISLibraryReader.read(data)

        if case .path(let p) = result.cells[0].elements[0] {
            #expect(p.pathType == .halfWidthExtend)
        } else {
            Issue.record("Expected path element")
        }
    }

    // MARK: - Bug 5: RECTANGLE S-bit (square)

    @Test func testSquareRectangleSBit() throws {
        // Build raw OASIS with a RECTANGLE record that has S-bit set (square: H=W).
        var w = OASISWriter()
        w.writeMagic()

        // START
        w.writeByte(OASISRecordType.start.rawValue)
        w.writeAString("1.0")
        w.writeReal(0.001)
        w.writeUnsignedInteger(0)

        // CELLNAME
        w.writeByte(OASISRecordType.cellname.rawValue)
        w.writeAString("SQTEST")

        // CELL (by ref)
        w.writeByte(OASISRecordType.cellRef.rawValue)
        w.writeUnsignedInteger(0)

        // RECTANGLE with S-bit set
        w.writeByte(OASISRecordType.rectangle.rawValue)
        // info-byte: S(7)=1, W(6)=1, H(5)=0 (H not present, inferred from W), X(4)=1, Y(3)=1, R(2)=0, D(1)=1, L(0)=1
        let infoByte: UInt8 = 0b1101_1011
        w.writeByte(infoByte)
        w.writeUnsignedInteger(1)     // L (layer)
        w.writeUnsignedInteger(0)     // D (datatype)
        w.writeUnsignedInteger(150)   // W (width = 150, height should also be 150)
        // H is NOT written because S-bit is set
        w.writeSignedInteger(10)      // X
        w.writeSignedInteger(20)      // Y

        // END
        w.writeByte(OASISRecordType.end.rawValue)
        w.writeAString("")
        w.writeUnsignedInteger(0)

        let result = try OASISLibraryReader.read(w.data)
        #expect(result.cells.count == 1)
        #expect(result.cells[0].elements.count == 1)

        if case .boundary(let b) = result.cells[0].elements[0] {
            // Should be a 150x150 square at (10,20)
            let xs = b.points[0...3].map(\.x)
            let ys = b.points[0...3].map(\.y)
            let width = (xs.max() ?? 0) - (xs.min() ?? 0)
            let height = (ys.max() ?? 0) - (ys.min() ?? 0)
            #expect(width == 150)
            #expect(height == 150)
            #expect(b.points[0] == IRPoint(x: 10, y: 20))
        } else {
            Issue.record("Expected boundary element for square rectangle")
        }
    }

    // MARK: - Bug 6: START record offset-flag table

    @Test func testStartRecordOffsetFlag() throws {
        var w = OASISWriter()
        w.writeMagic()

        // START with offset-flag = 1 (tables present)
        w.writeByte(OASISRecordType.start.rawValue)
        w.writeAString("1.0")
        w.writeReal(0.001)
        w.writeUnsignedInteger(1) // offset-flag = 1 (non-zero)

        // 12 dummy table values (6 tables x 2 values each)
        for _ in 0..<12 {
            w.writeUnsignedInteger(0)
        }

        // CELLNAME
        w.writeByte(OASISRecordType.cellname.rawValue)
        w.writeAString("OFFTEST")

        // CELL (by ref)
        w.writeByte(OASISRecordType.cellRef.rawValue)
        w.writeUnsignedInteger(0)

        // Simple RECTANGLE
        w.writeByte(OASISRecordType.rectangle.rawValue)
        let rectInfo: UInt8 = 0b0111_1011
        w.writeByte(rectInfo)
        w.writeUnsignedInteger(1)     // L
        w.writeUnsignedInteger(0)     // D
        w.writeUnsignedInteger(50)    // W
        w.writeUnsignedInteger(50)    // H
        w.writeSignedInteger(0)       // X
        w.writeSignedInteger(0)       // Y

        // END
        w.writeByte(OASISRecordType.end.rawValue)
        w.writeAString("")
        w.writeUnsignedInteger(0)

        // Must parse successfully without misaligned reads
        let result = try OASISLibraryReader.read(w.data)
        #expect(result.cells.count == 1)
        #expect(result.cells[0].name == "OFFTEST")
        #expect(result.cells[0].elements.count == 1)
    }

    // MARK: - Bug 7: CTRAPEZOID type 25 rejected

    @Test func testCTrapezoidType25Rejected() throws {
        #expect(throws: OASISError.self) {
            _ = try ctrapezoidPoints(type: 25, x: 0, y: 0, w: 100, h: 100)
        }
    }
}
