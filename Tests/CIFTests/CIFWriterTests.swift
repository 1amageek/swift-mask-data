import Testing
import Foundation
import LayoutIR
@testable import CIF

@Suite("CIF Writer")
struct CIFWriterTests {

    @Test func writeEmptyLibrary() throws {
        let lib = IRLibrary(name: "empty", units: .default, cells: [])
        let data = try CIFLibraryWriter.write(lib)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("E"))
    }

    @Test func writeSingleBox() throws {
        let cell = IRCell(name: "CELL_1", elements: [
            .boundary(IRBoundary(layer: 1, datatype: 0, points: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 100, y: 0),
                IRPoint(x: 100, y: 50),
                IRPoint(x: 0, y: 50),
                IRPoint(x: 0, y: 0),
            ], properties: []))
        ])
        let lib = IRLibrary(name: "test", units: .default, cells: [cell])
        let data = try CIFLibraryWriter.write(lib)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("B 100 50 50 25"))
        #expect(text.contains("L 1"))
        #expect(text.contains("DS 1"))
        #expect(text.contains("DF"))
    }

    @Test func writePolygon() throws {
        let cell = IRCell(name: "CELL_1", elements: [
            .boundary(IRBoundary(layer: 1, datatype: 0, points: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 100, y: 0),
                IRPoint(x: 50, y: 100),
                IRPoint(x: 0, y: 0),
            ], properties: []))
        ])
        let lib = IRLibrary(name: "test", units: .default, cells: [cell])
        let data = try CIFLibraryWriter.write(lib)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("P 0 0 100 0 50 100"))
    }

    @Test func writePath() throws {
        let cell = IRCell(name: "CELL_1", elements: [
            .path(IRPath(layer: 1, datatype: 0, pathType: .flush,
                        width: 200, points: [
                            IRPoint(x: 0, y: 0),
                            IRPoint(x: 1000, y: 0),
                        ], properties: []))
        ])
        let lib = IRLibrary(name: "test", units: .default, cells: [cell])
        let data = try CIFLibraryWriter.write(lib)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("W 200 0 0 1000 0"))
    }

    @Test func writeText() throws {
        let cell = IRCell(name: "CELL_1", elements: [
            .text(IRText(layer: 1, texttype: 0, transform: .identity,
                        position: IRPoint(x: 500, y: 600),
                        string: "VDD", properties: []))
        ])
        let lib = IRLibrary(name: "test", units: .default, cells: [cell])
        let data = try CIFLibraryWriter.write(lib)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("9 VDD 500 600"))
    }

    @Test func writeCellRef() throws {
        let cells = [
            IRCell(name: "CHILD", elements: []),
            IRCell(name: "TOP", elements: [
                .cellRef(IRCellRef(cellName: "CHILD",
                                   origin: IRPoint(x: 100, y: 200),
                                   transform: .identity,
                                   properties: []))
            ])
        ]
        let lib = IRLibrary(name: "test", units: .default, cells: cells)
        let data = try CIFLibraryWriter.write(lib)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("C 1 T 100 200"))
    }

    @Test func writeCellRefWithMirror() throws {
        let cells = [
            IRCell(name: "CHILD", elements: []),
            IRCell(name: "TOP", elements: [
                .cellRef(IRCellRef(cellName: "CHILD",
                                   origin: IRPoint(x: 0, y: 0),
                                   transform: IRTransform(mirrorX: true, magnification: 1.0, angle: 0),
                                   properties: []))
            ])
        ]
        let lib = IRLibrary(name: "test", units: .default, cells: cells)
        let data = try CIFLibraryWriter.write(lib)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("M Y"))
    }

    @Test func writeMultipleLayers() throws {
        let cell = IRCell(name: "CELL_1", elements: [
            .boundary(IRBoundary(layer: 1, datatype: 0, points: [
                IRPoint(x: 0, y: 0), IRPoint(x: 10, y: 0),
                IRPoint(x: 10, y: 10), IRPoint(x: 0, y: 10), IRPoint(x: 0, y: 0),
            ], properties: [])),
            .boundary(IRBoundary(layer: 2, datatype: 0, points: [
                IRPoint(x: 0, y: 0), IRPoint(x: 20, y: 0),
                IRPoint(x: 20, y: 20), IRPoint(x: 0, y: 20), IRPoint(x: 0, y: 0),
            ], properties: [])),
        ])
        let lib = IRLibrary(name: "test", units: .default, cells: [cell])
        let data = try CIFLibraryWriter.write(lib)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("L 1"))
        #expect(text.contains("L 2"))
    }

    @Test func roundTripBox() throws {
        let cell = IRCell(name: "CELL_1", elements: [
            .boundary(IRBoundary(layer: 1, datatype: 0, points: [
                IRPoint(x: 100, y: 200),
                IRPoint(x: 500, y: 200),
                IRPoint(x: 500, y: 400),
                IRPoint(x: 100, y: 400),
                IRPoint(x: 100, y: 200),
            ], properties: []))
        ])
        let lib = IRLibrary(name: "test", units: .default, cells: [cell])
        let data = try CIFLibraryWriter.write(lib)
        let result = try CIFLibraryReader.read(data)

        #expect(result.cells.count == 1)
        #expect(result.cells[0].elements.count == 1)
        if case .boundary(let b) = result.cells[0].elements[0] {
            let xs = b.points.map(\.x)
            let ys = b.points.map(\.y)
            #expect(xs.min()! == 100)
            #expect(xs.max()! == 500)
            #expect(ys.min()! == 200)
            #expect(ys.max()! == 400)
        } else {
            Issue.record("Expected boundary")
        }
    }

    @Test func roundTripPolygon() throws {
        let cell = IRCell(name: "CELL_1", elements: [
            .boundary(IRBoundary(layer: 1, datatype: 0, points: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 100, y: 0),
                IRPoint(x: 50, y: 100),
                IRPoint(x: 0, y: 0),
            ], properties: []))
        ])
        let lib = IRLibrary(name: "test", units: .default, cells: [cell])
        let data = try CIFLibraryWriter.write(lib)
        let result = try CIFLibraryReader.read(data)
        if case .boundary(let b) = result.cells[0].elements[0] {
            #expect(b.points.count == 4) // auto-closed
        }
    }

    @Test func roundTripPath() throws {
        let cell = IRCell(name: "CELL_1", elements: [
            .path(IRPath(layer: 1, datatype: 0, pathType: .flush,
                        width: 200, points: [
                            IRPoint(x: 0, y: 0),
                            IRPoint(x: 500, y: 0),
                            IRPoint(x: 500, y: 500),
                        ], properties: []))
        ])
        let lib = IRLibrary(name: "test", units: .default, cells: [cell])
        let data = try CIFLibraryWriter.write(lib)
        let result = try CIFLibraryReader.read(data)
        if case .path(let p) = result.cells[0].elements[0] {
            #expect(p.width == 200)
            #expect(p.points.count == 3)
        }
    }
}

@Suite("CIF Reader Direction Vector")
struct CIFDirectionVectorTests {

    @Test func boxWithDirectionVector() throws {
        // Box of length 100, width 50, at center (200,200), direction (0,1) → 90 degree rotation
        let cif = """
        DS 1 1;
        L 1;
        B 100 50 200 200 0 1;
        DF;
        E
        """
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        #expect(lib.cells.count == 1)
        if case .boundary(let b) = lib.cells[0].elements[0] {
            #expect(b.points.count == 5)
            // With direction (0,1), the box is rotated 90 degrees
            // length along Y, width along X
            let xs = b.points.map(\.x)
            let ys = b.points.map(\.y)
            // Center should be at (200, 200)
            let midX = (xs.min()! + xs.max()!) / 2
            let midY = (ys.min()! + ys.max()!) / 2
            #expect(midX == 200)
            #expect(midY == 200)
        }
    }

    @Test func boxWithDefaultDirection() throws {
        // Box with direction (1,0) should be same as no direction
        let cif = """
        DS 1 1;
        L 1;
        B 100 50 200 200 1 0;
        DF;
        E
        """
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        if case .boundary(let b) = lib.cells[0].elements[0] {
            let xs = b.points.map(\.x)
            let ys = b.points.map(\.y)
            #expect(xs.min()! == 150)
            #expect(xs.max()! == 250)
            #expect(ys.min()! == 175)
            #expect(ys.max()! == 225)
        }
    }

    @Test func boxWithoutDirection() throws {
        // Box without direction vector
        let cif = """
        DS 1 1;
        L 1;
        B 100 50 200 200;
        DF;
        E
        """
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        if case .boundary(let b) = lib.cells[0].elements[0] {
            let xs = b.points.map(\.x)
            let ys = b.points.map(\.y)
            #expect(xs.min()! == 150)
            #expect(xs.max()! == 250)
            #expect(ys.min()! == 175)
            #expect(ys.max()! == 225)
        }
    }
}
