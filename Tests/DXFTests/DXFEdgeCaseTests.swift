import CircuiteFoundation
import Testing
import Foundation
import LayoutIR
@testable import DXF

@Suite("DXF Group Reader Edge Cases")
struct DXFGroupReaderEdgeCaseTests {

    @Test func emptyInput() throws {
        #expect(try DXFGroupReader.read("").isEmpty)
    }

    @Test func oddNumberOfLines() {
        #expect(throws: DXFError.incompleteGroup(line: 3)) {
            try DXFGroupReader.read("  0\nLINE\n  8")
        }
    }

    @Test func trailingWhitespace() throws {
        let groups = try DXFGroupReader.read("  0  \nSECTION  \n")
        #expect(groups.count == 1)
        #expect(groups[0].value == "SECTION")
    }

    @Test func windowsLineEndings() throws {
        let groups = try DXFGroupReader.read("  0\r\nSECTION\r\n  2\r\nENTITIES\r\n")
        #expect(groups.map(\.value) == ["SECTION", "ENTITIES"])
    }

    @Test func outOfRangeGroupCode() {
        #expect(throws: DXFError.invalidGroupCode(line: 1, value: "1072")) {
            try DXFGroupReader.read("1072\nvalue")
        }
    }

    @Test func nonNumericGroupCode() {
        #expect(throws: DXFError.invalidGroupCode(line: 1, value: "abc")) {
            try DXFGroupReader.read("abc\nvalue\n  0\nEOF")
        }
    }
}

@Suite("DXF Reader Edge Cases")
struct DXFReaderEdgeCaseTests {

    @Test func invalidEncoding() throws {
        let data = Data([0xFF, 0xFE, 0x00, 0x01])
        do {
            _ = try DXFLibraryReader.read(data, databaseUnitScale: try testDatabaseUnitScale())
            Issue.record("Should have thrown")
        } catch let error as DXFError {
            #expect(error == .invalidEncoding)
        }
    }

    @Test func malformedCoordinateFailsClosed() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nLINE\n 10\nnot-a-number\n 20\n0\n 11\n1\n 21\n1\n  0\nENDSEC\n  0\nEOF\n"
        do {
            _ = try DXFLibraryReader.read(Data(dxf.utf8), databaseUnitScale: try testDatabaseUnitScale())
            Issue.record("Expected malformed coordinate to fail")
        } catch let error as DXFError {
            #expect(error == .invalidNumber(entity: "LINE", groupCode: 10, value: "not-a-number"))
        }
    }

    @Test func unsupportedEntityFailsClosed() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nPOINT\n 10\n0\n 20\n0\n  0\nENDSEC\n  0\nEOF\n"
        do {
            _ = try DXFLibraryReader.read(Data(dxf.utf8), databaseUnitScale: try testDatabaseUnitScale())
            Issue.record("Expected unsupported entity to fail")
        } catch let error as DXFError {
            #expect(error == .unsupportedEntity("POINT"))
        }
    }

    @Test func unterminatedSectionFailsClosed() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nEOF\n"
        do {
            _ = try DXFLibraryReader.read(Data(dxf.utf8), databaseUnitScale: try testDatabaseUnitScale())
            Issue.record("Expected unterminated section to fail")
        } catch let error as DXFError {
            #expect(error == .invalidStructure("EOF occurred before nested structures were closed"))
        }
    }

    @Test func lineWithIdenticalEndpoints() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nLINE\n  8\n1\n 10\n5.0\n 20\n5.0\n 11\n5.0\n 21\n5.0\n  0\nENDSEC\n  0\nEOF\n"
        let lib = try DXFLibraryReader.read(Data(dxf.utf8), databaseUnitScale: try testDatabaseUnitScale())
        if case .path(let p) = lib.cells[0].elements[0] {
            #expect(p.points[0] == p.points[1])
        } else {
            Issue.record("Expected path")
        }
    }

    @Test func lineWithNegativeCoordinates() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nLINE\n  8\n1\n 10\n-10.0\n 20\n-20.0\n 11\n30.0\n 21\n40.0\n  0\nENDSEC\n  0\nEOF\n"
        let lib = try DXFLibraryReader.read(Data(dxf.utf8), databaseUnitScale: try testDatabaseUnitScale())
        if case .path(let p) = lib.cells[0].elements[0] {
            #expect(p.points[0] == IRPoint(x: -10000, y: -20000))
            #expect(p.points[1] == IRPoint(x: 30000, y: 40000))
        } else {
            Issue.record("Expected path")
        }
    }

    @Test func circleApproximation() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nCIRCLE\n  8\n1\n 10\n0.0\n 20\n0.0\n 40\n1.0\n  0\nENDSEC\n  0\nEOF\n"
        let lib = try DXFLibraryReader.read(Data(dxf.utf8), databaseUnitScale: try testDatabaseUnitScale())
        if case .boundary(let b) = lib.cells[0].elements[0] {
            // 64 segments + close = 65 points
            #expect(b.points.count == 65)
            // First and last should be the same (closed polygon)
            #expect(b.points.first == b.points.last)
            // Verify radius: all points should be ~1000 DBU from center
            for p in b.points {
                let dist = sqrt(Double(p.x * p.x + p.y * p.y))
                #expect(abs(dist - 1000.0) < 50.0) // Allow rounding tolerance
            }
        } else {
            Issue.record("Expected boundary from CIRCLE")
        }
    }

    @Test func circleWithZeroRadius() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nCIRCLE\n  8\n1\n 10\n0.0\n 20\n0.0\n 40\n0.0\n  0\nENDSEC\n  0\nEOF\n"
        do {
            _ = try DXFLibraryReader.read(Data(dxf.utf8), databaseUnitScale: try testDatabaseUnitScale())
            Issue.record("Expected strict radius validation to fail")
        } catch let error as DXFError {
            #expect(error == .invalidNumber(entity: "CIRCLE", groupCode: 40, value: "0.0"))
        }
    }

    @Test func textWithEmptyString() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nTEXT\n  8\n1\n 10\n0.0\n 20\n0.0\n  1\n\n  0\nENDSEC\n  0\nEOF\n"
        do {
            _ = try DXFLibraryReader.read(Data(dxf.utf8), databaseUnitScale: try testDatabaseUnitScale())
            Issue.record("Expected empty text to fail")
        } catch let error as DXFError {
            #expect(error == .invalidGeometry("TEXT contains empty text"))
        }
    }

    @Test func customUnits() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nLINE\n  8\n1\n 10\n1.0\n 20\n2.0\n 11\n3.0\n 21\n4.0\n  0\nENDSEC\n  0\nEOF\n"
        let lib = try DXFLibraryReader.read(Data(dxf.utf8), databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 100))
        if case .path(let p) = lib.cells[0].elements[0] {
            #expect(p.points[0] == IRPoint(x: 100, y: 200))
            #expect(p.points[1] == IRPoint(x: 300, y: 400))
        } else {
            Issue.record("Expected path")
        }
    }

    @Test func derivedCircleCoordinateOverflowFailsClosed() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nCIRCLE\n  8\n1\n 10\n2147000\n 20\n0\n 40\n1000\n  0\nENDSEC\n  0\nEOF\n"
        do {
            _ = try DXFLibraryReader.read(
                Data(dxf.utf8),
                databaseUnitScale: try testDatabaseUnitScale()
            )
            Issue.record("Expected derived coordinate overflow to fail")
        } catch let error as DXFError {
            guard case .coordinateOutOfRange(let entity, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(entity == "CIRCLE")
        }
    }

    @Test func incompleteOldStylePolylineFailsClosed() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nPOLYLINE\n 70\n0\n  0\nVERTEX\n 10\n0\n 20\n0\n  0\nSEQEND\n  0\nENDSEC\n  0\nEOF\n"
        #expect(throws: DXFError.invalidGeometry("POLYLINE requires at least 2 complete vertices")) {
            try DXFLibraryReader.read(
                Data(dxf.utf8),
                databaseUnitScale: try testDatabaseUnitScale()
            )
        }
    }

    @Test func hatchDeclaredEdgeCountMismatchFailsClosed() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nHATCH\n 91\n1\n 92\n0\n 93\n2\n 72\n1\n 10\n0\n 20\n0\n 11\n1\n 21\n0\n  0\nENDSEC\n  0\nEOF\n"
        #expect(throws: DXFError.invalidStructure("HATCH edge count does not match group 93")) {
            try DXFLibraryReader.read(
                Data(dxf.utf8),
                databaseUnitScale: try testDatabaseUnitScale()
            )
        }
    }

    @Test func hatchPolylineWithMisorderedCoordinatePairsFailsClosed() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nHATCH\n 91\n1\n 92\n2\n 72\n0\n 73\n1\n 93\n3\n 10\n0\n 10\n1\n 20\n0\n 20\n1\n 10\n0\n 20\n2\n  0\nENDSEC\n  0\nEOF\n"
        #expect(throws: DXFError.invalidStructure(
            "HATCH polyline coordinates must be ordered as complete group 10/20 pairs"
        )) {
            try DXFLibraryReader.read(
                Data(dxf.utf8),
                databaseUnitScale: try testDatabaseUnitScale()
            )
        }
    }

    @Test func multipleEntityTypes() throws {
        let dxf = """
          0\nSECTION\n  2\nENTITIES\n  0\nLINE\n  8\n1\n 10\n0\n 20\n0\n 11\n10\n 21\n0\n  0\nTEXT\n  8\n1\n 10\n5\n 20\n5\n  1\nHello\n  0\nLWPOLYLINE\n  8\n2\n 70\n1\n 10\n0\n 20\n0\n 10\n10\n 20\n0\n 10\n10\n 20\n10\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8), databaseUnitScale: try testDatabaseUnitScale())
        let elements = lib.cells[0].elements
        #expect(elements.count == 3)
        if case .path = elements[0] { } else { Issue.record("Expected path at 0") }
        if case .text = elements[1] { } else { Issue.record("Expected text at 1") }
        if case .boundary = elements[2] { } else { Issue.record("Expected boundary at 2") }
    }

    @Test func insertWithMissingBlock() throws {
        // INSERT referencing non-existent block should still parse
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nINSERT\n  2\nMISSING\n 10\n0\n 20\n0\n  0\nENDSEC\n  0\nEOF\n"
        let lib = try DXFLibraryReader.read(Data(dxf.utf8), databaseUnitScale: try testDatabaseUnitScale())
        if case .cellRef(let ref) = lib.cells[0].elements[0] {
            #expect(ref.cellName == "MISSING")
        } else {
            Issue.record("Expected cellRef")
        }
    }

    @Test func fileWithOnlyEOF() throws {
        let dxf = "  0\nEOF\n"
        let lib = try DXFLibraryReader.read(Data(dxf.utf8), databaseUnitScale: try testDatabaseUnitScale())
        #expect(lib.cells.isEmpty)
    }
}
