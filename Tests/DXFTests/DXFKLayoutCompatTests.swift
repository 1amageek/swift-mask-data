import Testing
import Foundation
import LayoutIR
@testable import DXF

@Suite("DXF ARC Entity")
struct DXFArcTests {

    @Test func semicircularArc() throws {
        let dxf = """
          0\nSECTION\n  2\nENTITIES\n  0\nARC\n  8\n1\n 10\n0.0\n 20\n0.0\n 40\n10.0\n 50\n0.0\n 51\n180.0\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        #expect(lib.cells.count == 1)
        if case .path(let p) = lib.cells[0].elements[0] {
            #expect(p.points.count == 65) // 64 segments + 1
            // First point should be at (10000, 0) - right side
            #expect(p.points[0] == IRPoint(x: 10000, y: 0))
            // Last point should be near (-10000, 0) - left side
            #expect(abs(p.points.last!.x - (-10000)) < 10)
            #expect(abs(p.points.last!.y) < 10)
        } else {
            Issue.record("Expected path from ARC")
        }
    }

    @Test func quarterArc() throws {
        let dxf = """
          0\nSECTION\n  2\nENTITIES\n  0\nARC\n  8\n1\n 10\n5.0\n 20\n5.0\n 40\n5.0\n 50\n0.0\n 51\n90.0\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        if case .path(let p) = lib.cells[0].elements[0] {
            // Start at angle 0: (10000, 5000)
            #expect(p.points[0] == IRPoint(x: 10000, y: 5000))
            // End at angle 90: (5000, 10000)
            let last = p.points.last!
            #expect(abs(last.x - 5000) < 10)
            #expect(abs(last.y - 10000) < 10)
        } else {
            Issue.record("Expected path from ARC")
        }
    }

    @Test func arcWithZeroRadius() throws {
        let dxf = """
          0\nSECTION\n  2\nENTITIES\n  0\nARC\n  8\n1\n 10\n0.0\n 20\n0.0\n 40\n0.0\n 50\n0.0\n 51\n90.0\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        #expect(lib.cells.isEmpty)
    }
}

@Suite("DXF ELLIPSE Entity")
struct DXFEllipseTests {

    @Test func fullEllipse() throws {
        // Major axis along X, length 10, ratio 0.5 → minor = 5
        let dxf = """
          0\nSECTION\n  2\nENTITIES\n  0\nELLIPSE\n  8\n1\n 10\n0.0\n 20\n0.0\n 11\n10.0\n 21\n0.0\n 40\n0.5\n 41\n0.0\n 42\n6.283185\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        if case .boundary(let b) = lib.cells[0].elements[0] {
            #expect(b.points.count == 65) // closed polygon
            // Major axis extends to ±10 in X
            let xs = b.points.map(\.x)
            let ys = b.points.map(\.y)
            #expect(xs.max()! >= 9900) // ~10000
            #expect(xs.min()! <= -9900)
            // Minor axis extends to ±5 in Y
            #expect(ys.max()! >= 4900) // ~5000
            #expect(ys.min()! <= -4900)
        } else {
            Issue.record("Expected boundary from full ELLIPSE")
        }
    }

    @Test func partialEllipse() throws {
        let dxf = """
          0\nSECTION\n  2\nENTITIES\n  0\nELLIPSE\n  8\n1\n 10\n0.0\n 20\n0.0\n 11\n10.0\n 21\n0.0\n 40\n0.5\n 41\n0.0\n 42\n3.14159\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        if case .path(let p) = lib.cells[0].elements[0] {
            #expect(p.points.count >= 2)
        } else {
            Issue.record("Expected path from partial ELLIPSE")
        }
    }
}

@Suite("DXF POLYLINE Entity (Old-Style)")
struct DXFPolylineTests {

    @Test func openPolyline() throws {
        let dxf = """
          0\nSECTION\n  2\nENTITIES\n  0\nPOLYLINE\n  8\n1\n 70\n0\n  0\nVERTEX\n 10\n0.0\n 20\n0.0\n  0\nVERTEX\n 10\n10.0\n 20\n0.0\n  0\nVERTEX\n 10\n10.0\n 20\n10.0\n  0\nSEQEND\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        #expect(lib.cells.count == 1)
        if case .path(let p) = lib.cells[0].elements[0] {
            #expect(p.points.count == 3)
            #expect(p.points[0] == IRPoint(x: 0, y: 0))
            #expect(p.points[1] == IRPoint(x: 10000, y: 0))
            #expect(p.points[2] == IRPoint(x: 10000, y: 10000))
        } else {
            Issue.record("Expected path from open POLYLINE")
        }
    }

    @Test func closedPolyline() throws {
        let dxf = """
          0\nSECTION\n  2\nENTITIES\n  0\nPOLYLINE\n  8\n1\n 70\n1\n  0\nVERTEX\n 10\n0.0\n 20\n0.0\n  0\nVERTEX\n 10\n10.0\n 20\n0.0\n  0\nVERTEX\n 10\n10.0\n 20\n10.0\n  0\nSEQEND\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        if case .boundary(let b) = lib.cells[0].elements[0] {
            #expect(b.points.count == 4) // 3 vertices + close
            #expect(b.points.first == b.points.last)
        } else {
            Issue.record("Expected boundary from closed POLYLINE")
        }
    }

    @Test func polylineWithBulge() throws {
        // Two vertices with a bulge creating a semicircle
        let dxf = """
          0\nSECTION\n  2\nENTITIES\n  0\nPOLYLINE\n  8\n1\n 70\n0\n  0\nVERTEX\n 10\n0.0\n 20\n0.0\n 42\n1.0\n  0\nVERTEX\n 10\n10.0\n 20\n0.0\n  0\nSEQEND\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        if case .path(let p) = lib.cells[0].elements[0] {
            // Should have the start, arc intermediate points, and end
            #expect(p.points.count > 2)
            #expect(p.points[0] == IRPoint(x: 0, y: 0))
            #expect(p.points.last == IRPoint(x: 10000, y: 0))
        } else {
            Issue.record("Expected path from POLYLINE with bulge")
        }
    }
}

@Suite("DXF LWPOLYLINE Bulge")
struct DXFLWPolylineBulgeTests {

    @Test func lwpolylineWithBulge() throws {
        let dxf = """
          0\nSECTION\n  2\nENTITIES\n  0\nLWPOLYLINE\n  8\n1\n 70\n0\n 10\n0.0\n 20\n0.0\n 42\n1.0\n 10\n10.0\n 20\n0.0\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        if case .path(let p) = lib.cells[0].elements[0] {
            #expect(p.points.count > 2)
            #expect(p.points[0] == IRPoint(x: 0, y: 0))
            #expect(p.points.last == IRPoint(x: 10000, y: 0))
        } else {
            Issue.record("Expected path from LWPOLYLINE with bulge")
        }
    }
}

@Suite("DXF INSERT Transform")
struct DXFInsertTransformTests {

    @Test func insertWithScale() throws {
        let dxf = """
          0\nSECTION\n  2\nBLOCKS\n  0\nBLOCK\n  2\nBLK1\n  0\nENDBLK\n  0\nENDSEC\n  0\nSECTION\n  2\nENTITIES\n  0\nINSERT\n  2\nBLK1\n 10\n0.0\n 20\n0.0\n 41\n2.0\n 42\n2.0\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        let topCell = lib.cells[0]
        if case .cellRef(let ref) = topCell.elements[0] {
            #expect(ref.cellName == "BLK1")
            #expect(abs(ref.transform.magnification - 2.0) < 0.01)
        } else {
            Issue.record("Expected cellRef with scale")
        }
    }

    @Test func insertWithRotation() throws {
        let dxf = """
          0\nSECTION\n  2\nBLOCKS\n  0\nBLOCK\n  2\nBLK1\n  0\nENDBLK\n  0\nENDSEC\n  0\nSECTION\n  2\nENTITIES\n  0\nINSERT\n  2\nBLK1\n 10\n0.0\n 20\n0.0\n 50\n90.0\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        let topCell = lib.cells[0]
        if case .cellRef(let ref) = topCell.elements[0] {
            #expect(abs(ref.transform.angle - 90.0) < 0.01)
        } else {
            Issue.record("Expected cellRef with rotation")
        }
    }

    @Test func insertWithMirror() throws {
        let dxf = """
          0\nSECTION\n  2\nBLOCKS\n  0\nBLOCK\n  2\nBLK1\n  0\nENDBLK\n  0\nENDSEC\n  0\nSECTION\n  2\nENTITIES\n  0\nINSERT\n  2\nBLK1\n 10\n0.0\n 20\n0.0\n 41\n-1.0\n 42\n1.0\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        let topCell = lib.cells[0]
        if case .cellRef(let ref) = topCell.elements[0] {
            #expect(ref.transform.mirrorX == true)
        } else {
            Issue.record("Expected cellRef with mirror")
        }
    }

    @Test func insertArray() throws {
        let dxf = """
          0\nSECTION\n  2\nBLOCKS\n  0\nBLOCK\n  2\nBLK1\n  0\nENDBLK\n  0\nENDSEC\n  0\nSECTION\n  2\nENTITIES\n  0\nINSERT\n  2\nBLK1\n 10\n0.0\n 20\n0.0\n 70\n3\n 71\n2\n 44\n10.0\n 45\n20.0\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        let topCell = lib.cells[0]
        if case .arrayRef(let aref) = topCell.elements[0] {
            #expect(aref.cellName == "BLK1")
            #expect(aref.columns == 3)
            #expect(aref.rows == 2)
            #expect(aref.referencePoints.count == 3)
        } else {
            Issue.record("Expected arrayRef from array INSERT")
        }
    }
}

@Suite("DXF HATCH Entity")
struct DXFHatchTests {

    @Test func hatchWithPolylineBoundary() throws {
        let dxf = """
          0\nSECTION\n  2\nENTITIES\n  0\nHATCH\n  8\n1\n 91\n1\n 92\n3\n 72\n0\n 73\n1\n 93\n4\n 10\n0.0\n 20\n0.0\n 10\n10.0\n 20\n0.0\n 10\n10.0\n 20\n10.0\n 10\n0.0\n 20\n10.0\n 75\n0\n 76\n0\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        #expect(lib.cells.count == 1)
        if case .boundary(let b) = lib.cells[0].elements[0] {
            // 4 vertices + close = 5 points
            #expect(b.points.count == 5)
            #expect(b.points.first == b.points.last)
        } else {
            Issue.record("Expected boundary from HATCH")
        }
    }
}

@Suite("DXF SPLINE Entity")
struct DXFSplineTests {

    @Test func splineWithFitPoints() throws {
        let dxf = """
          0\nSECTION\n  2\nENTITIES\n  0\nSPLINE\n  8\n1\n 70\n0\n 11\n0.0\n 21\n0.0\n 11\n5.0\n 21\n10.0\n 11\n10.0\n 21\n0.0\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        if case .path(let p) = lib.cells[0].elements[0] {
            #expect(p.points.count == 3)
            #expect(p.points[0] == IRPoint(x: 0, y: 0))
            #expect(p.points[1] == IRPoint(x: 5000, y: 10000))
            #expect(p.points[2] == IRPoint(x: 10000, y: 0))
        } else {
            Issue.record("Expected path from SPLINE")
        }
    }

    @Test func closedSpline() throws {
        let dxf = """
          0\nSECTION\n  2\nENTITIES\n  0\nSPLINE\n  8\n1\n 70\n1\n 11\n0.0\n 21\n0.0\n 11\n10.0\n 21\n0.0\n 11\n10.0\n 21\n10.0\n 11\n0.0\n 21\n10.0\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        if case .boundary(let b) = lib.cells[0].elements[0] {
            #expect(b.points.first == b.points.last) // closed
        } else {
            Issue.record("Expected boundary from closed SPLINE")
        }
    }
}

@Suite("DXF ATTDEF Entity")
struct DXFAttdefTests {

    @Test func attdefAsText() throws {
        let dxf = """
          0\nSECTION\n  2\nENTITIES\n  0\nATTDEF\n  8\n1\n 10\n5.0\n 20\n10.0\n  2\nREFDES\n  1\nU1\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        if case .text(let t) = lib.cells[0].elements[0] {
            #expect(t.string == "REFDES") // Tag takes priority
            #expect(t.position == IRPoint(x: 5000, y: 10000))
        } else {
            Issue.record("Expected text from ATTDEF")
        }
    }
}

@Suite("DXF SOLID Entity")
struct DXFSolidTests {

    @Test func quadrilateralSolid() throws {
        let dxf = """
          0\nSECTION\n  2\nENTITIES\n  0\nSOLID\n  8\n1\n 10\n0.0\n 20\n0.0\n 11\n10.0\n 21\n0.0\n 12\n0.0\n 22\n10.0\n 13\n10.0\n 23\n10.0\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        if case .boundary(let b) = lib.cells[0].elements[0] {
            #expect(b.points.count == 5) // 4 points + close
            #expect(b.points.first == b.points.last)
        } else {
            Issue.record("Expected boundary from SOLID")
        }
    }

    @Test func triangularSolid() throws {
        // When point 3 == point 2, it's a triangle
        let dxf = """
          0\nSECTION\n  2\nENTITIES\n  0\nSOLID\n  8\n1\n 10\n0.0\n 20\n0.0\n 11\n10.0\n 21\n0.0\n 12\n5.0\n 22\n10.0\n 13\n5.0\n 23\n10.0\n  0\nENDSEC\n  0\nEOF
        """
        let lib = try DXFLibraryReader.read(Data(dxf.utf8))
        if case .boundary(let b) = lib.cells[0].elements[0] {
            #expect(b.points.count == 4) // triangle + close
        } else {
            Issue.record("Expected boundary from triangular SOLID")
        }
    }
}

@Suite("DXF Read Options")
struct DXFReadOptionsTests {

    @Test func customCircleSegments() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nCIRCLE\n  8\n1\n 10\n0.0\n 20\n0.0\n 40\n1.0\n  0\nENDSEC\n  0\nEOF\n"
        let options = DXFLibraryReader.Options(circleSegments: 16)
        let lib = try DXFLibraryReader.read(Data(dxf.utf8), options: options)
        if case .boundary(let b) = lib.cells[0].elements[0] {
            #expect(b.points.count == 17) // 16 segments + 1
        } else {
            Issue.record("Expected boundary")
        }
    }

    @Test func layerMapping() throws {
        let dxf = "  0\nSECTION\n  2\nENTITIES\n  0\nLINE\n  8\nMETAL1\n 10\n0\n 20\n0\n 11\n1\n 21\n0\n  0\nENDSEC\n  0\nEOF\n"
        let options = DXFLibraryReader.Options(
            layerMapping: ["METAL1": (layer: 42, datatype: 0)]
        )
        let lib = try DXFLibraryReader.read(Data(dxf.utf8), options: options)
        if case .path(let p) = lib.cells[0].elements[0] {
            #expect(p.layer == 42)
        } else {
            Issue.record("Expected path")
        }
    }
}

@Suite("DXF Writer")
struct DXFWriterTests {

    @Test func writeEmptyLibrary() throws {
        let lib = IRLibrary(name: "empty", units: .default, cells: [])
        let data = try DXFLibraryWriter.write(lib)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("SECTION"))
        #expect(text.contains("EOF"))
    }

    @Test func writeLine() throws {
        let cell = IRCell(name: "TOP", elements: [
            .path(IRPath(layer: 1, datatype: 0, pathType: .flush, width: 0, points: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 10000, y: 5000),
            ], properties: []))
        ])
        let lib = IRLibrary(name: "test", units: .default, cells: [cell])
        let data = try DXFLibraryWriter.write(lib)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("LINE"))
        #expect(text.contains("10.0")) // 10000/1000
        #expect(text.contains("5.0"))  // 5000/1000
    }

    @Test func writeBoundary() throws {
        let cell = IRCell(name: "TOP", elements: [
            .boundary(IRBoundary(layer: 1, datatype: 0, points: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 10000, y: 0),
                IRPoint(x: 10000, y: 10000),
                IRPoint(x: 0, y: 10000),
                IRPoint(x: 0, y: 0),
            ], properties: []))
        ])
        let lib = IRLibrary(name: "test", units: .default, cells: [cell])
        let data = try DXFLibraryWriter.write(lib)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("LWPOLYLINE"))
    }

    @Test func writeText() throws {
        let cell = IRCell(name: "TOP", elements: [
            .text(IRText(layer: 1, texttype: 0, transform: .identity,
                        position: IRPoint(x: 5000, y: 3000),
                        string: "VDD", properties: []))
        ])
        let lib = IRLibrary(name: "test", units: .default, cells: [cell])
        let data = try DXFLibraryWriter.write(lib)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("TEXT"))
        #expect(text.contains("VDD"))
    }

    @Test func writeBlocksAndInsert() throws {
        let cells = [
            IRCell(name: "TOP", elements: [
                .cellRef(IRCellRef(cellName: "CHILD",
                                   origin: IRPoint(x: 1000, y: 2000),
                                   transform: .identity,
                                   properties: []))
            ]),
            IRCell(name: "CHILD", elements: [
                .path(IRPath(layer: 1, datatype: 0, pathType: .flush, width: 0, points: [
                    IRPoint(x: 0, y: 0), IRPoint(x: 1000, y: 0),
                ], properties: []))
            ])
        ]
        let lib = IRLibrary(name: "test", units: .default, cells: cells)
        let data = try DXFLibraryWriter.write(lib)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("BLOCK"))
        #expect(text.contains("CHILD"))
        #expect(text.contains("INSERT"))
    }

    @Test func writeArrayRef() throws {
        let cells = [
            IRCell(name: "TOP", elements: [
                .arrayRef(IRArrayRef(
                    cellName: "CHILD",
                    transform: .identity,
                    columns: 3,
                    rows: 2,
                    referencePoints: [
                        IRPoint(x: 0, y: 0),
                        IRPoint(x: 30000, y: 0),
                        IRPoint(x: 0, y: 20000),
                    ],
                    properties: []))
            ]),
            IRCell(name: "CHILD", elements: [])
        ]
        let lib = IRLibrary(name: "test", units: .default, cells: cells)
        let data = try DXFLibraryWriter.write(lib)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("INSERT"))
        #expect(text.contains("CHILD"))
    }

    @Test func writeWithLayerMapping() throws {
        let cell = IRCell(name: "TOP", elements: [
            .path(IRPath(layer: 1, datatype: 0, pathType: .flush, width: 0, points: [
                IRPoint(x: 0, y: 0), IRPoint(x: 1000, y: 0),
            ], properties: []))
        ])
        let lib = IRLibrary(name: "test", units: .default, cells: [cell])
        let options = DXFLibraryWriter.Options(layerMapping: [1: "METAL1"])
        let data = try DXFLibraryWriter.write(lib, options: options)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("METAL1"))
    }

    @Test func roundTripLine() throws {
        let cell = IRCell(name: "TOP", elements: [
            .path(IRPath(layer: 1, datatype: 0, pathType: .flush, width: 0, points: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 10000, y: 5000),
            ], properties: []))
        ])
        let lib = IRLibrary(name: "test", units: .default, cells: [cell])
        let data = try DXFLibraryWriter.write(lib)
        let result = try DXFLibraryReader.read(data)
        #expect(result.cells.count == 1)
        if case .path(let p) = result.cells[0].elements[0] {
            #expect(p.points[0] == IRPoint(x: 0, y: 0))
            #expect(p.points[1] == IRPoint(x: 10000, y: 5000))
        } else {
            Issue.record("Expected path in round-trip")
        }
    }

    @Test func roundTripBoundary() throws {
        let cell = IRCell(name: "TOP", elements: [
            .boundary(IRBoundary(layer: 2, datatype: 0, points: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 10000, y: 0),
                IRPoint(x: 10000, y: 10000),
                IRPoint(x: 0, y: 10000),
                IRPoint(x: 0, y: 0),
            ], properties: []))
        ])
        let lib = IRLibrary(name: "test", units: .default, cells: [cell])
        let data = try DXFLibraryWriter.write(lib)
        let result = try DXFLibraryReader.read(data)
        if case .boundary(let b) = result.cells[0].elements[0] {
            let xs = b.points.map(\.x)
            let ys = b.points.map(\.y)
            #expect(xs.min()! == 0)
            #expect(xs.max()! == 10000)
            #expect(ys.min()! == 0)
            #expect(ys.max()! == 10000)
        } else {
            Issue.record("Expected boundary in round-trip")
        }
    }

    @Test func roundTripText() throws {
        let cell = IRCell(name: "TOP", elements: [
            .text(IRText(layer: 1, texttype: 0, transform: .identity,
                        position: IRPoint(x: 5000, y: 3000),
                        string: "GND", properties: []))
        ])
        let lib = IRLibrary(name: "test", units: .default, cells: [cell])
        let data = try DXFLibraryWriter.write(lib)
        let result = try DXFLibraryReader.read(data)
        if case .text(let t) = result.cells[0].elements[0] {
            #expect(t.string == "GND")
            #expect(t.position == IRPoint(x: 5000, y: 3000))
        } else {
            Issue.record("Expected text in round-trip")
        }
    }
}
