import Testing
import Foundation
import LayoutIR
@testable import GDSII

@Suite("GDSLibraryWriter")
struct GDSLibraryWriterTests {

    @Test func writeMinimalLibrary() throws {
        let lib = IRLibrary(
            name: "EMPTY",
            units: .default,
            cells: [
                IRCell(name: "TOP")
            ]
        )
        let data = try GDSLibraryWriter.write(lib)
        // Should produce valid GDSII binary
        #expect(data.count > 0)
        // Verify starts with HEADER record
        #expect(data[2] == GDSRecordType.header.rawValue)
    }

    @Test func writeSingleBoundary() throws {
        let boundary = IRBoundary(
            layer: 1,
            datatype: 0,
            points: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 1000, y: 0),
                IRPoint(x: 1000, y: 1000),
                IRPoint(x: 0, y: 1000),
                IRPoint(x: 0, y: 0),
            ],
            properties: []
        )
        let lib = IRLibrary(
            name: "BNDTEST",
            units: .default,
            cells: [
                IRCell(name: "RECT", elements: [.boundary(boundary)])
            ]
        )
        let data = try GDSLibraryWriter.write(lib)
        #expect(data.count > 0)
    }

    @Test func writePathElement() throws {
        let path = IRPath(
            layer: 2,
            datatype: 0,
            pathType: .halfWidthExtend,
            width: 100,
            points: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 5000, y: 0),
            ],
            properties: []
        )
        let lib = IRLibrary(
            name: "PATHTEST",
            units: .default,
            cells: [
                IRCell(name: "WIRE", elements: [.path(path)])
            ]
        )
        let data = try GDSLibraryWriter.write(lib)
        #expect(data.count > 0)
    }

    @Test func writeTextElement() throws {
        let text = IRText(
            layer: 3,
            texttype: 0,
            transform: .identity,
            position: IRPoint(x: 500, y: 500),
            string: "VDD",
            properties: []
        )
        let lib = IRLibrary(
            name: "TXTTEST",
            units: .default,
            cells: [
                IRCell(name: "LABEL", elements: [.text(text)])
            ]
        )
        let data = try GDSLibraryWriter.write(lib)
        #expect(data.count > 0)
    }

    @Test func writeSrefElement() throws {
        let child = IRCell(name: "CHILD", elements: [
            .boundary(IRBoundary(
                layer: 1, datatype: 0,
                points: [
                    IRPoint(x: 0, y: 0), IRPoint(x: 100, y: 0),
                    IRPoint(x: 100, y: 100), IRPoint(x: 0, y: 100),
                    IRPoint(x: 0, y: 0)
                ],
                properties: []
            ))
        ])
        let parent = IRCell(name: "PARENT", elements: [
            .cellRef(IRCellRef(
                cellName: "CHILD",
                origin: IRPoint(x: 1000, y: 2000),
                transform: .identity,
                properties: []
            ))
        ])
        let lib = IRLibrary(
            name: "SREFTEST",
            units: .default,
            cells: [child, parent]
        )
        let data = try GDSLibraryWriter.write(lib)
        #expect(data.count > 0)
    }

    @Test func writeArefElement() throws {
        let cell = IRCell(name: "UNIT")
        let top = IRCell(name: "ARRAY", elements: [
            .arrayRef(IRArrayRef(
                cellName: "UNIT",
                transform: .identity,
                columns: 4,
                rows: 3,
                referencePoints: [
                    IRPoint(x: 0, y: 0),
                    IRPoint(x: 4000, y: 0),
                    IRPoint(x: 0, y: 3000),
                ],
                properties: []
            ))
        ])
        let lib = IRLibrary(
            name: "AREFTEST",
            units: .default,
            cells: [cell, top]
        )
        let data = try GDSLibraryWriter.write(lib)
        #expect(data.count > 0)
    }
}

@Suite("GDSLibraryReader")
struct GDSLibraryReaderTests {

    @Test func readMinimalLibrary() throws {
        let lib = IRLibrary(
            name: "EMPTY",
            units: .default,
            cells: [IRCell(name: "TOP")]
        )
        let data = try GDSLibraryWriter.write(lib)
        let result = try GDSLibraryReader.read(data)
        #expect(result.name == "EMPTY")
        #expect(result.cells.count == 1)
        #expect(result.cells[0].name == "TOP")
        #expect(result.cells[0].elements.isEmpty)
    }

    @Test func readBoundaryRoundTrip() throws {
        let boundary = IRBoundary(
            layer: 5,
            datatype: 2,
            points: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 2000, y: 0),
                IRPoint(x: 2000, y: 1000),
                IRPoint(x: 0, y: 1000),
                IRPoint(x: 0, y: 0),
            ],
            properties: []
        )
        let original = IRLibrary(
            name: "BNDLIB",
            units: .default,
            cells: [IRCell(name: "RECT", elements: [.boundary(boundary)])]
        )
        let data = try GDSLibraryWriter.write(original)
        let result = try GDSLibraryReader.read(data)

        #expect(result.cells.count == 1)
        #expect(result.cells[0].elements.count == 1)
        if case .boundary(let b) = result.cells[0].elements[0] {
            #expect(b.layer == 5)
            #expect(b.datatype == 2)
            #expect(b.points.count == 5)
            #expect(b.points[0] == IRPoint(x: 0, y: 0))
            #expect(b.points[1] == IRPoint(x: 2000, y: 0))
            #expect(b.points[4] == IRPoint(x: 0, y: 0))
        } else {
            Issue.record("Expected boundary element")
        }
    }

    @Test func readPathRoundTrip() throws {
        let path = IRPath(
            layer: 10,
            datatype: 0,
            pathType: .halfWidthExtend,
            width: 200,
            points: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 3000, y: 0),
                IRPoint(x: 3000, y: 1000),
            ],
            properties: []
        )
        let original = IRLibrary(
            name: "PATHLIB",
            units: .default,
            cells: [IRCell(name: "WIRE", elements: [.path(path)])]
        )
        let data = try GDSLibraryWriter.write(original)
        let result = try GDSLibraryReader.read(data)

        #expect(result.cells[0].elements.count == 1)
        if case .path(let p) = result.cells[0].elements[0] {
            #expect(p.layer == 10)
            #expect(p.width == 200)
            #expect(p.pathType == .halfWidthExtend)
            #expect(p.points.count == 3)
        } else {
            Issue.record("Expected path element")
        }
    }

    @Test func readTextRoundTrip() throws {
        let text = IRText(
            layer: 6,
            texttype: 1,
            transform: .identity,
            position: IRPoint(x: 500, y: 500),
            string: "GND",
            properties: []
        )
        let original = IRLibrary(
            name: "TXTLIB",
            units: .default,
            cells: [IRCell(name: "LABEL", elements: [.text(text)])]
        )
        let data = try GDSLibraryWriter.write(original)
        let result = try GDSLibraryReader.read(data)

        if case .text(let t) = result.cells[0].elements[0] {
            #expect(t.layer == 6)
            #expect(t.string == "GND")
            #expect(t.position == IRPoint(x: 500, y: 500))
        } else {
            Issue.record("Expected text element")
        }
    }

    @Test func readSrefRoundTrip() throws {
        let child = IRCell(name: "SUB", elements: [
            .boundary(IRBoundary(
                layer: 1, datatype: 0,
                points: [
                    IRPoint(x: 0, y: 0), IRPoint(x: 100, y: 0),
                    IRPoint(x: 100, y: 100), IRPoint(x: 0, y: 100),
                    IRPoint(x: 0, y: 0),
                ],
                properties: []
            ))
        ])
        let parent = IRCell(name: "TOP", elements: [
            .cellRef(IRCellRef(
                cellName: "SUB",
                origin: IRPoint(x: 500, y: 600),
                transform: .identity,
                properties: []
            ))
        ])
        let original = IRLibrary(
            name: "HIERLIB",
            units: .default,
            cells: [child, parent]
        )
        let data = try GDSLibraryWriter.write(original)
        let result = try GDSLibraryReader.read(data)

        #expect(result.cells.count == 2)
        let topCell = result.cell(named: "TOP")
        #expect(topCell != nil)
        if case .cellRef(let ref) = topCell?.elements[0] {
            #expect(ref.cellName == "SUB")
            #expect(ref.origin == IRPoint(x: 500, y: 600))
        } else {
            Issue.record("Expected cellRef element")
        }
    }

    @Test func readArefRoundTrip() throws {
        let unit = IRCell(name: "UNIT", elements: [
            .boundary(IRBoundary(
                layer: 1, datatype: 0,
                points: [
                    IRPoint(x: 0, y: 0), IRPoint(x: 50, y: 0),
                    IRPoint(x: 50, y: 50), IRPoint(x: 0, y: 50),
                    IRPoint(x: 0, y: 0),
                ],
                properties: []
            ))
        ])
        let top = IRCell(name: "GRID", elements: [
            .arrayRef(IRArrayRef(
                cellName: "UNIT",
                transform: .identity,
                columns: 8,
                rows: 4,
                referencePoints: [
                    IRPoint(x: 0, y: 0),
                    IRPoint(x: 800, y: 0),
                    IRPoint(x: 0, y: 400),
                ],
                properties: []
            ))
        ])
        let original = IRLibrary(
            name: "ARLIB",
            units: .default,
            cells: [unit, top]
        )
        let data = try GDSLibraryWriter.write(original)
        let result = try GDSLibraryReader.read(data)

        let gridCell = result.cell(named: "GRID")
        #expect(gridCell != nil)
        if case .arrayRef(let ar) = gridCell?.elements[0] {
            #expect(ar.cellName == "UNIT")
            #expect(ar.columns == 8)
            #expect(ar.rows == 4)
            #expect(ar.referencePoints.count == 3)
        } else {
            Issue.record("Expected arrayRef element")
        }
    }

    @Test func readUnitsRoundTrip() throws {
        let units = IRUnits(dbuPerMicron: 100)
        let original = IRLibrary(
            name: "ULIB",
            units: units,
            cells: [IRCell(name: "A")]
        )
        let data = try GDSLibraryWriter.write(original)
        let result = try GDSLibraryReader.read(data)

        let relError = abs(result.units.dbuPerMicron - 100.0) / 100.0
        #expect(relError < 1e-6)
    }

    @Test func readMixedElementsRoundTrip() throws {
        let cell = IRCell(name: "MIX", elements: [
            .boundary(IRBoundary(
                layer: 1, datatype: 0,
                points: [
                    IRPoint(x: 0, y: 0), IRPoint(x: 100, y: 0),
                    IRPoint(x: 100, y: 100), IRPoint(x: 0, y: 100),
                    IRPoint(x: 0, y: 0),
                ],
                properties: []
            )),
            .path(IRPath(
                layer: 2, datatype: 0,
                pathType: .flush, width: 50,
                points: [IRPoint(x: 0, y: 0), IRPoint(x: 500, y: 0)],
                properties: []
            )),
            .text(IRText(
                layer: 3, texttype: 0,
                transform: .identity,
                position: IRPoint(x: 200, y: 200),
                string: "HELLO",
                properties: []
            )),
        ])
        let original = IRLibrary(
            name: "MIXLIB",
            units: .default,
            cells: [cell]
        )
        let data = try GDSLibraryWriter.write(original)
        let result = try GDSLibraryReader.read(data)

        #expect(result.cells[0].elements.count == 3)
        if case .boundary = result.cells[0].elements[0] { } else {
            Issue.record("Expected boundary at index 0")
        }
        if case .path = result.cells[0].elements[1] { } else {
            Issue.record("Expected path at index 1")
        }
        if case .text = result.cells[0].elements[2] { } else {
            Issue.record("Expected text at index 2")
        }
    }

    @Test func readTransformRoundTrip() throws {
        let cell = IRCell(name: "XFORM", elements: [
            .cellRef(IRCellRef(
                cellName: "XFORM",
                origin: IRPoint(x: 100, y: 200),
                transform: IRTransform(mirrorX: true, magnification: 2.0, angle: 90.0),
                properties: []
            ))
        ])
        let original = IRLibrary(
            name: "XLIB",
            units: .default,
            cells: [cell]
        )
        let data = try GDSLibraryWriter.write(original)
        let result = try GDSLibraryReader.read(data)

        if case .cellRef(let ref) = result.cells[0].elements[0] {
            #expect(ref.transform.mirrorX == true)
            let magErr = abs(ref.transform.magnification - 2.0)
            #expect(magErr < 1e-6)
            let angleErr = abs(ref.transform.angle - 90.0)
            #expect(angleErr < 1e-6)
        } else {
            Issue.record("Expected cellRef element")
        }
    }
}
