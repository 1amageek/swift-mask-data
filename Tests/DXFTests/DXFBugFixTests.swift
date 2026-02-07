import Testing
import Foundation
import LayoutIR
@testable import DXF

@Suite("DXF Bug Fixes")
struct DXFBugFixTests {

    @Test func testHatchEllipticalArcDegrees() throws {
        // Create a DXF HATCH with an elliptical arc edge (edge type 3).
        // Group 50=0 (start angle in degrees), 51=180 (end angle in degrees).
        // The arc should cover half the ellipse.
        let dxf = [
            "  0", "SECTION",
            "  2", "ENTITIES",
            "  0", "HATCH",
            "  8", "1",
            // boundary path type: edge boundary (not polyline)
            " 92", "0",
            // number of edges
            " 93", "1",
            // edge type 3 = elliptical arc
            " 72", "3",
            // center
            " 10", "0.0",
            " 20", "0.0",
            // major axis endpoint relative to center
            " 11", "10.0",
            " 21", "0.0",
            // minor/major ratio
            " 40", "0.5",
            // start angle in degrees
            " 50", "0",
            // end angle in degrees
            " 51", "180",
            "  0", "ENDSEC",
            "  0", "EOF",
        ].joined(separator: "\n")

        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        #expect(!lib.cells.isEmpty)

        // Find the boundary element from the hatch
        var foundBoundary = false
        for cell in lib.cells {
            for element in cell.elements {
                if case .boundary(let b) = element {
                    foundBoundary = true
                    // The elliptical arc from 0 to 180 degrees should produce points
                    // covering the upper half of the ellipse (positive Y values mostly).
                    // With center at (0,0), major axis 10 along X, ratio 0.5 (minor=5),
                    // the first point should be near (10000, 0) and the last near (-10000, 0).
                    // Points in between should have positive Y.
                    let pts = b.points
                    #expect(pts.count > 2)
                    // Check that the arc actually spans half the ellipse:
                    // The first point should be near the positive X end
                    let firstX = Double(pts[0].x)
                    #expect(firstX > 5000) // Near major axis positive end (10*1000=10000 dbu)
                    // The last non-closing point should be near the negative X end
                    let lastIdx = pts.count > 1 && pts.first == pts.last ? pts.count - 2 : pts.count - 1
                    let lastX = Double(pts[lastIdx].x)
                    #expect(lastX < -5000) // Near major axis negative end

                    // At least some intermediate points should have positive Y
                    // (covering upper half of ellipse)
                    let hasPositiveY = pts.dropFirst().dropLast().contains { $0.y > 1000 }
                    #expect(hasPositiveY)
                }
            }
        }
        #expect(foundBoundary)
    }

    @Test func testDXFEllipseFullBothZero() throws {
        // ELLIPSE with startParam=0 and endParam=0 means a full ellipse.
        // It should produce a boundary (not a path).
        let dxf = [
            "  0", "SECTION",
            "  2", "ENTITIES",
            "  0", "ELLIPSE",
            "  8", "1",
            // center
            " 10", "0.0",
            " 20", "0.0",
            // major axis endpoint relative to center
            " 11", "10.0",
            " 21", "0.0",
            // minor/major ratio
            " 40", "0.5",
            // startParam = 0
            " 41", "0.0",
            // endParam = 0 (means full ellipse)
            " 42", "0.0",
            "  0", "ENDSEC",
            "  0", "EOF",
        ].joined(separator: "\n")

        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        #expect(!lib.cells.isEmpty)

        var foundBoundary = false
        for cell in lib.cells {
            for element in cell.elements {
                if case .boundary(let b) = element {
                    foundBoundary = true
                    // Full ellipse should have many points forming a closed polygon
                    #expect(b.points.count > 10)
                    // First and last points should be the same (closed)
                    #expect(b.points.first == b.points.last)
                } else if case .path(_) = element {
                    Issue.record("Full ellipse should produce boundary, not path")
                }
            }
        }
        #expect(foundBoundary)
    }

    @Test func testInsertNonUniformScale() throws {
        // Create a DXF with INSERT having scaleX=2, scaleY=3 (non-uniform)
        let dxf = [
            "  0", "SECTION",
            "  2", "BLOCKS",
            "  0", "BLOCK",
            "  2", "MYBLK",
            "  0", "LINE",
            "  8", "1",
            " 10", "0",
            " 20", "0",
            " 11", "1",
            " 21", "1",
            "  0", "ENDBLK",
            "  0", "ENDSEC",
            "  0", "SECTION",
            "  2", "ENTITIES",
            "  0", "INSERT",
            "  2", "MYBLK",
            " 10", "0.0",
            " 20", "0.0",
            " 41", "2.0",
            " 42", "3.0",
            "  0", "ENDSEC",
            "  0", "EOF",
        ].joined(separator: "\n")

        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        // TOP cell should have the INSERT
        let topCell = lib.cells[0]
        if case .cellRef(let ref) = topCell.elements[0] {
            #expect(ref.cellName == "MYBLK")
            // Geometric mean of 2 and 3 = sqrt(6) ~ 2.449
            let expectedMag = (2.0 * 3.0).squareRoot()
            #expect(abs(ref.transform.magnification - expectedMag) < 0.01)
            // Should not be mirrored (both scales positive)
            #expect(ref.transform.mirrorX == false)
        } else {
            Issue.record("Expected cellRef from INSERT")
        }
    }

    @Test func testInsertUniformScale() throws {
        // Verify uniform scaling still works correctly
        let dxf = [
            "  0", "SECTION",
            "  2", "BLOCKS",
            "  0", "BLOCK",
            "  2", "BLK",
            "  0", "LINE",
            "  8", "1",
            " 10", "0",
            " 20", "0",
            " 11", "1",
            " 21", "1",
            "  0", "ENDBLK",
            "  0", "ENDSEC",
            "  0", "SECTION",
            "  2", "ENTITIES",
            "  0", "INSERT",
            "  2", "BLK",
            " 10", "0.0",
            " 20", "0.0",
            " 41", "2.0",
            " 42", "2.0",
            "  0", "ENDSEC",
            "  0", "EOF",
        ].joined(separator: "\n")

        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        let topCell = lib.cells[0]
        if case .cellRef(let ref) = topCell.elements[0] {
            #expect(abs(ref.transform.magnification - 2.0) < 1e-9)
        } else {
            Issue.record("Expected cellRef from INSERT")
        }
    }
}
