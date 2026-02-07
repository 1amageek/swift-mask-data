import Testing
import Foundation
import LayoutIR
@testable import OASIS

/// Regression tests for OASIS reader/writer bug fixes.
@Suite("OASIS Bug Fix Regressions")
struct OASISBugFixTests {

    // MARK: - Bug 1: Rectangle W/H bit order

    @Test func testRectangleWHBitOrder() throws {
        // Non-square rectangle: w=100, h=200. If W/H bits are swapped,
        // the reader would produce w=200, h=100.
        let boundary = IRBoundary(
            layer: 1,
            datatype: 0,
            points: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 100, y: 0),
                IRPoint(x: 100, y: 200),
                IRPoint(x: 0, y: 200),
                IRPoint(x: 0, y: 0),
            ],
            properties: []
        )
        let lib = IRLibrary(
            name: "RECTWHTEST",
            units: .default,
            cells: [IRCell(name: "R", elements: [.boundary(boundary)])]
        )
        let data = try OASISLibraryWriter.write(lib)
        let result = try OASISLibraryReader.read(data)

        #expect(result.cells.count == 1)
        #expect(result.cells[0].elements.count == 1)
        if case .boundary(let b) = result.cells[0].elements[0] {
            // Verify the rectangle corners match a 100-wide, 200-tall box
            #expect(b.points.count == 5)
            #expect(b.points[0] == IRPoint(x: 0, y: 0))
            #expect(b.points[1] == IRPoint(x: 100, y: 0))
            #expect(b.points[2] == IRPoint(x: 100, y: 200))
            #expect(b.points[3] == IRPoint(x: 0, y: 200))
            #expect(b.points[4] == IRPoint(x: 0, y: 0))
        } else {
            Issue.record("Expected boundary element")
        }
    }

    @Test func testNonSquareRectangleRoundTrip() throws {
        // Wide rectangle: w=500, h=100
        let boundary = IRBoundary(
            layer: 3,
            datatype: 1,
            points: [
                IRPoint(x: 10, y: 20),
                IRPoint(x: 510, y: 20),
                IRPoint(x: 510, y: 120),
                IRPoint(x: 10, y: 120),
                IRPoint(x: 10, y: 20),
            ],
            properties: []
        )
        let lib = IRLibrary(
            name: "WIDERECT",
            units: .default,
            cells: [IRCell(name: "WR", elements: [.boundary(boundary)])]
        )
        let data = try OASISLibraryWriter.write(lib)
        let result = try OASISLibraryReader.read(data)

        if case .boundary(let b) = result.cells[0].elements[0] {
            #expect(b.layer == 3)
            #expect(b.datatype == 1)
            #expect(b.points.count == 5)
            // Check the width (x-extent) and height (y-extent)
            let xs = b.points[0...3].map(\.x)
            let ys = b.points[0...3].map(\.y)
            let width = (xs.max() ?? 0) - (xs.min() ?? 0)
            let height = (ys.max() ?? 0) - (ys.min() ?? 0)
            #expect(width == 500)
            #expect(height == 100)
        } else {
            Issue.record("Expected boundary element")
        }
    }

    // MARK: - Bug 2: Repetition reuse (type-0)

    @Test func testRepetitionReuse() throws {
        // Build OASIS data manually with two rectangles, the second using
        // repetition type-0 (reuse). This exercises the readRepetitionWithReuse
        // code path that previously double-read the type-0 byte.
        var w = OASISWriter()
        w.writeMagic()

        // START
        w.writeByte(OASISRecordType.start.rawValue)
        w.writeAString("1.0")
        w.writeReal(0.001) // 1000 dbu/um
        w.writeUnsignedInteger(0)

        // CELLNAME
        w.writeByte(OASISRecordType.cellname.rawValue)
        w.writeAString("REPTEST")

        // CELL (by ref)
        w.writeByte(OASISRecordType.cellRef.rawValue)
        w.writeUnsignedInteger(0)

        // First RECTANGLE with repetition (uniform row, 3 copies, spacing 100)
        w.writeByte(OASISRecordType.rectangle.rawValue)
        // info-byte: S(7)=0, W(6)=1, H(5)=1, X(4)=1, Y(3)=1, R(2)=1, D(1)=1, L(0)=1
        let firstInfoByte: UInt8 = 0b0111_1111
        w.writeByte(firstInfoByte)
        w.writeUnsignedInteger(1)     // L (layer)
        w.writeUnsignedInteger(0)     // D (datatype)
        w.writeUnsignedInteger(50)    // W
        w.writeUnsignedInteger(30)    // H
        w.writeSignedInteger(0)       // X
        w.writeSignedInteger(0)       // Y
        // Repetition: type 2 = uniform row, count=3, spacing=100
        w.writeUnsignedInteger(2)     // type 2
        w.writeUnsignedInteger(1)     // count - 2 = 1
        w.writeUnsignedInteger(100)   // spacing

        // Second RECTANGLE reusing previous repetition (type-0)
        w.writeByte(OASISRecordType.rectangle.rawValue)
        // info-byte: S(7)=0, W(6)=1, H(5)=1, X(4)=1, Y(3)=1, R(2)=1, D(1)=0, L(0)=0
        // Reuse layer/datatype from modal, set W, H, X, Y, R
        let secondInfoByte: UInt8 = 0b0111_1100
        w.writeByte(secondInfoByte)
        w.writeUnsignedInteger(60)    // W
        w.writeUnsignedInteger(40)    // H
        w.writeSignedInteger(0)       // X
        w.writeSignedInteger(200)     // Y
        // Repetition type-0: reuse previous (single byte 0x00)
        w.writeByte(0x00)

        // END
        w.writeByte(OASISRecordType.end.rawValue)
        w.writeAString("")
        w.writeUnsignedInteger(0)

        let result = try OASISLibraryReader.read(w.data)
        #expect(result.cells.count == 1)
        #expect(result.cells[0].elements.count == 2)

        // Verify first rectangle
        if case .boundary(let b1) = result.cells[0].elements[0] {
            #expect(b1.layer == 1)
            let xs = b1.points[0...3].map(\.x)
            let ys = b1.points[0...3].map(\.y)
            #expect((xs.max() ?? 0) - (xs.min() ?? 0) == 50)
            #expect((ys.max() ?? 0) - (ys.min() ?? 0) == 30)
        } else {
            Issue.record("Expected boundary for first rectangle")
        }

        // Verify second rectangle dimensions are correct (not corrupted by double-read)
        if case .boundary(let b2) = result.cells[0].elements[1] {
            let xs = b2.points[0...3].map(\.x)
            let ys = b2.points[0...3].map(\.y)
            #expect((xs.max() ?? 0) - (xs.min() ?? 0) == 60)
            #expect((ys.max() ?? 0) - (ys.min() ?? 0) == 40)
        } else {
            Issue.record("Expected boundary for second rectangle")
        }
    }

    // MARK: - Bug 3: Array placement field order

    @Test func testArrayPlacementFieldOrder() throws {
        let child = IRCell(name: "UNIT", elements: [
            .boundary(IRBoundary(
                layer: 1, datatype: 0,
                points: [
                    IRPoint(x: 0, y: 0), IRPoint(x: 10, y: 0),
                    IRPoint(x: 10, y: 10), IRPoint(x: 0, y: 10),
                    IRPoint(x: 0, y: 0),
                ],
                properties: []
            ))
        ])
        let arrayRef = IRArrayRef(
            cellName: "UNIT",
            transform: .identity,
            columns: 4,
            rows: 3,
            referencePoints: [
                IRPoint(x: 100, y: 200),                   // origin
                IRPoint(x: 100 + 4 * 50, y: 200),          // column vector end
                IRPoint(x: 100, y: 200 + 3 * 80),          // row vector end
            ],
            properties: []
        )
        let parent = IRCell(name: "ARRAY_TOP", elements: [.arrayRef(arrayRef)])
        let lib = IRLibrary(
            name: "AREFTEST",
            units: .default,
            cells: [child, parent]
        )
        let data = try OASISLibraryWriter.write(lib)
        let result = try OASISLibraryReader.read(data)

        // Find the ARRAY_TOP cell
        let topCell = result.cell(named: "ARRAY_TOP")
        #expect(topCell != nil)
        guard let top = topCell else { return }
        #expect(top.elements.count == 1)

        if case .arrayRef(let aref) = top.elements[0] {
            #expect(aref.cellName == "UNIT")
            #expect(aref.columns == 4)
            #expect(aref.rows == 3)
            #expect(aref.referencePoints.count == 3)
            #expect(aref.referencePoints[0] == IRPoint(x: 100, y: 200))
        } else {
            Issue.record("Expected arrayRef element, got \(top.elements[0])")
        }
    }

    // MARK: - Bug 4: Property value count

    @Test func testPropertyValueCount() throws {
        // Build OASIS data manually with a property record containing 3 values.
        // The property info-byte encodes the value count in the lower bits.
        // This verifies the count is not truncated by the extra & 0x07 mask.
        var w = OASISWriter()
        w.writeMagic()

        // START
        w.writeByte(OASISRecordType.start.rawValue)
        w.writeAString("1.0")
        w.writeReal(0.001)
        w.writeUnsignedInteger(0)

        // CELLNAME
        w.writeByte(OASISRecordType.cellname.rawValue)
        w.writeAString("PROPTEST")

        // CELL (by ref)
        w.writeByte(OASISRecordType.cellRef.rawValue)
        w.writeUnsignedInteger(0)

        // RECTANGLE (simple, as a target for the property)
        w.writeByte(OASISRecordType.rectangle.rawValue)
        // info-byte: W, H, X, Y, D, L set
        let rectInfo: UInt8 = 0b0111_1011
        w.writeByte(rectInfo)
        w.writeUnsignedInteger(1)     // L
        w.writeUnsignedInteger(0)     // D
        w.writeUnsignedInteger(100)   // W
        w.writeUnsignedInteger(100)   // H
        w.writeSignedInteger(0)       // X
        w.writeSignedInteger(0)       // Y

        // PROPERTY record with 3 string values
        // OASIS spec info-byte layout: UUUU(7:4) V(3) C(2) T(1) S(0)
        // UUUU=0011 (3 values), V=0 (values in stream), C=1 (name present), T=0 (inline), S=0
        // Bits: 0011(7:4) 0(3) 1(2) 0(1) 0(0) = 0b0011_0100 = 0x34
        let propInfoByte: UInt8 = 0x34
        w.writeByte(OASISRecordType.property.rawValue)
        w.writeByte(propInfoByte)
        w.writeAString("test_prop")       // inline property name
        // 3 property values (type 3 = a-string)
        w.writePropertyValue(.aString("alpha"))
        w.writePropertyValue(.aString("beta"))
        w.writePropertyValue(.aString("gamma"))

        // END
        w.writeByte(OASISRecordType.end.rawValue)
        w.writeAString("")
        w.writeUnsignedInteger(0)

        let result = try OASISLibraryReader.read(w.data)
        #expect(result.cells.count == 1)
        #expect(result.cells[0].elements.count == 1)

        if case .boundary(let b) = result.cells[0].elements[0] {
            // The property should be attached with all 3 values
            #expect(b.properties.count == 1)
            let prop = b.properties[0]
            #expect(prop.value.contains("test_prop"))
            #expect(prop.value.contains("alpha"))
            #expect(prop.value.contains("beta"))
            #expect(prop.value.contains("gamma"))
        } else {
            Issue.record("Expected boundary element with property")
        }
    }
}
