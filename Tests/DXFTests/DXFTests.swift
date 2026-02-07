import Testing
import Foundation
import LayoutIR
@testable import DXF

// MARK: - DXF Error Tests

@Suite("DXFError")
struct DXFErrorTests {

    @Test func invalidEncodingEquality() {
        let a: DXFError = .invalidEncoding
        let b: DXFError = .invalidEncoding
        #expect(a == b)
    }
}

// MARK: - DXF Group Reader Tests

@Suite("DXFGroupReader")
struct DXFGroupReaderTests {

    @Test func singlePair() {
        let text = "  0\nSECTION"
        let groups = DXFGroupReader.read(text)
        #expect(groups.count == 1)
        #expect(groups[0].code == 0)
        #expect(groups[0].value == "SECTION")
    }

    @Test func multiplePairs() {
        let text = "  0\nLINE\n 10\n1.5\n 20\n2.5\n 11\n10.0\n 21\n20.0"
        let groups = DXFGroupReader.read(text)
        #expect(groups.count == 5)
        #expect(groups[0].code == 0)
        #expect(groups[0].value == "LINE")
        #expect(groups[1].code == 10)
        #expect(groups[1].value == "1.5")
    }
}

// MARK: - DXF Reader Tests

@Suite("DXFLibraryReader")
struct DXFLibraryReaderTests {

    @Test func emptyEntities() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nENDSEC\n  0\nEOF\n"
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        #expect(lib.cells.isEmpty)
    }

    @Test func lineEntity() throws {
        let dxf = """
          0\nSECTION\n  2\nENTITIES\n  0\nLINE\n  8\n1\n 10\n0.0\n 20\n0.0\n 11\n10.0\n 21\n5.0\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        #expect(lib.cells.count == 1)
        if case .path(let p) = lib.cells[0].elements[0] {
            #expect(p.points.count == 2)
            #expect(p.points[0] == IRPoint(x: 0, y: 0))
            #expect(p.points[1] == IRPoint(x: 10000, y: 5000))
        } else {
            Issue.record("Expected path element")
        }
    }

    @Test func lwpolylineOpen() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nLWPOLYLINE\n  8\n1\n 70\n0\n 10\n0\n 20\n0\n 10\n10\n 20\n0\n 10\n10\n 20\n10\n  0\nENDSEC\n  0\nEOF\n"
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        if case .path(let p) = lib.cells[0].elements[0] {
            #expect(p.points.count == 3)
        } else {
            Issue.record("Expected path (open polyline)")
        }
    }

    @Test func lwpolylineClosed() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nLWPOLYLINE\n  8\n1\n 70\n1\n 10\n0\n 20\n0\n 10\n10\n 20\n0\n 10\n10\n 20\n10\n  0\nENDSEC\n  0\nEOF\n"
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        if case .boundary(let b) = lib.cells[0].elements[0] {
            #expect(b.points.count == 4)
            #expect(b.points[0] == b.points[3])
        } else {
            Issue.record("Expected boundary (closed polyline)")
        }
    }

    @Test func textEntity() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nTEXT\n  8\n2\n 10\n5.0\n 20\n5.0\n  1\nHello\n  0\nENDSEC\n  0\nEOF\n"
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        if case .text(let t) = lib.cells[0].elements[0] {
            #expect(t.string == "Hello")
            #expect(t.position == IRPoint(x: 5000, y: 5000))
        } else {
            Issue.record("Expected text element")
        }
    }

    @Test func blockAndInsert() throws {
        let dxf = """
          0\nSECTION\n  2\nBLOCKS\n  0\nBLOCK\n  2\nMYBLK\n  0\nLINE\n  8\n1\n 10\n0\n 20\n0\n 11\n1\n 21\n1\n  0\nENDBLK\n  0\nENDSEC\n  0\nSECTION\n  2\nENTITIES\n  0\nINSERT\n  2\nMYBLK\n 10\n5.0\n 20\n5.0\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        // MYBLK cell + TOP cell with INSERT
        #expect(lib.cells.count == 2)
        let topCell = lib.cells[0] // TOP is inserted at index 0
        if case .cellRef(let ref) = topCell.elements[0] {
            #expect(ref.cellName == "MYBLK")
            #expect(ref.origin == IRPoint(x: 5000, y: 5000))
        } else {
            Issue.record("Expected cellRef from INSERT")
        }
    }

    @Test func layerMapping() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nLINE\n  8\nMETAL1\n 10\n0\n 20\n0\n 11\n1\n 21\n0\n  0\nLINE\n  8\nPOLY\n 10\n0\n 20\n0\n 11\n1\n 21\n0\n  0\nLINE\n  8\nMETAL1\n 10\n0\n 20\n0\n 11\n2\n 21\n0\n  0\nENDSEC\n  0\nEOF\n"
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        let elements = lib.cells[0].elements
        #expect(elements.count == 3)
        // METAL1 and POLY should have different layers, second METAL1 should match first
        if case .path(let p1) = elements[0],
           case .path(let p2) = elements[1],
           case .path(let p3) = elements[2] {
            #expect(p1.layer == p3.layer)
            #expect(p1.layer != p2.layer)
        } else {
            Issue.record("Expected path elements")
        }
    }
}
