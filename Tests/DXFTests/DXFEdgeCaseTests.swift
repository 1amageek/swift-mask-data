import Testing
import Foundation
import LayoutIR
@testable import DXF

@Suite("DXF Group Reader Edge Cases")
struct DXFGroupReaderEdgeCaseTests {

    @Test func emptyInput() {
        #expect(DXFGroupReader.read("").isEmpty)
    }

    @Test func oddNumberOfLines() {
        // Incomplete pair at the end should be ignored
        let groups = DXFGroupReader.read("  0\nLINE\n  8")
        #expect(groups.count == 1)
        #expect(groups[0].code == 0)
    }

    @Test func trailingWhitespace() {
        let groups = DXFGroupReader.read("  0  \nSECTION  \n")
        #expect(groups.count == 1)
        #expect(groups[0].value == "SECTION")
    }

    @Test func nonNumericGroupCode() {
        // Non-numeric group code line should be skipped
        let groups = DXFGroupReader.read("abc\nvalue\n  0\nEOF")
        // First pair has non-numeric code, should skip
        #expect(groups.count == 1)
        #expect(groups[0].value == "EOF")
    }
}

@Suite("DXF Reader Edge Cases")
struct DXFReaderEdgeCaseTests {

    @Test func invalidEncoding() throws {
        let data = Data([0xFF, 0xFE, 0x00, 0x01])
        do {
            _ = try DXFLibraryReader.read(data)
            Issue.record("Should have thrown")
        } catch let error as DXFError {
            #expect(error == .invalidEncoding)
        }
    }

    @Test func lineWithIdenticalEndpoints() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nLINE\n  8\n1\n 10\n5.0\n 20\n5.0\n 11\n5.0\n 21\n5.0\n  0\nENDSEC\n  0\nEOF\n"
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        if case .path(let p) = lib.cells[0].elements[0] {
            #expect(p.points[0] == p.points[1])
        } else {
            Issue.record("Expected path")
        }
    }

    @Test func lineWithNegativeCoordinates() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nLINE\n  8\n1\n 10\n-10.0\n 20\n-20.0\n 11\n30.0\n 21\n40.0\n  0\nENDSEC\n  0\nEOF\n"
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        if case .path(let p) = lib.cells[0].elements[0] {
            #expect(p.points[0] == IRPoint(x: -10000, y: -20000))
            #expect(p.points[1] == IRPoint(x: 30000, y: 40000))
        } else {
            Issue.record("Expected path")
        }
    }

    @Test func circleApproximation() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nCIRCLE\n  8\n1\n 10\n0.0\n 20\n0.0\n 40\n1.0\n  0\nENDSEC\n  0\nEOF\n"
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
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
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        // Zero radius should produce no element
        #expect(lib.cells.isEmpty)
    }

    @Test func textWithEmptyString() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nTEXT\n  8\n1\n 10\n0.0\n 20\n0.0\n  1\n\n  0\nENDSEC\n  0\nEOF\n"
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        // Empty text should be skipped
        #expect(lib.cells.isEmpty)
    }

    @Test func customUnits() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nLINE\n  8\n1\n 10\n1.0\n 20\n2.0\n 11\n3.0\n 21\n4.0\n  0\nENDSEC\n  0\nEOF\n"
        let lib = try DXFLibraryReader.read(Data(dxf.utf8), units: IRUnits(dbuPerMicron: 100))
        if case .path(let p) = lib.cells[0].elements[0] {
            #expect(p.points[0] == IRPoint(x: 100, y: 200))
            #expect(p.points[1] == IRPoint(x: 300, y: 400))
        } else {
            Issue.record("Expected path")
        }
    }

    @Test func multipleEntityTypes() throws {
        let dxf = """
          0\nSECTION\n  2\nENTITIES\n  0\nLINE\n  8\n1\n 10\n0\n 20\n0\n 11\n10\n 21\n0\n  0\nTEXT\n  8\n1\n 10\n5\n 20\n5\n  1\nHello\n  0\nLWPOLYLINE\n  8\n2\n 70\n1\n 10\n0\n 20\n0\n 10\n10\n 20\n0\n 10\n10\n 20\n10\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        let elements = lib.cells[0].elements
        #expect(elements.count == 3)
        if case .path = elements[0] { } else { Issue.record("Expected path at 0") }
        if case .text = elements[1] { } else { Issue.record("Expected text at 1") }
        if case .boundary = elements[2] { } else { Issue.record("Expected boundary at 2") }
    }

    @Test func insertWithMissingBlock() throws {
        // INSERT referencing non-existent block should still parse
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nINSERT\n  2\nMISSING\n 10\n0\n 20\n0\n  0\nENDSEC\n  0\nEOF\n"
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        if case .cellRef(let ref) = lib.cells[0].elements[0] {
            #expect(ref.cellName == "MISSING")
        } else {
            Issue.record("Expected cellRef")
        }
    }

    @Test func fileWithOnlyEOF() throws {
        let dxf = "  0\nEOF\n"
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        #expect(lib.cells.isEmpty)
    }
}
