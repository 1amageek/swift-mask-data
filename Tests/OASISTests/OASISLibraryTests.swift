import Testing
import Foundation
import CircuiteFoundation
import LayoutIR
import GDSII
@testable import OASIS

// MARK: - Step 8: OASISLibraryWriter

@Suite("OASISLibraryWriter")
struct OASISLibraryWriterTests {

    @Test func writeMinimalLibrary() throws {
        let lib = IRLibrary(
            name: "EMPTY",
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
            cells: [IRCell(name: "TOP")]
        )
        let data = try OASISLibraryWriter.write(lib)
        #expect(data.count > 0)
        // Should start with OASIS magic
        let magic = Array("%SEMI-OASIS\r\n".utf8)
        #expect(Array(data.prefix(magic.count)) == magic)
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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
            cells: [
                IRCell(name: "RECT", elements: [.boundary(boundary)])
            ]
        )
        let data = try OASISLibraryWriter.write(lib)
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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
            cells: [
                IRCell(name: "WIRE", elements: [.path(path)])
            ]
        )
        let data = try OASISLibraryWriter.write(lib)
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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
            cells: [
                IRCell(name: "LABEL", elements: [.text(text)])
            ]
        )
        let data = try OASISLibraryWriter.write(lib)
        #expect(data.count > 0)
    }

    @Test func writePlacementElement() throws {
        let child = IRCell(name: "CHILD", elements: [
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
        let parent = IRCell(name: "PARENT", elements: [
            .cellRef(IRCellRef(
                cellName: "CHILD",
                origin: IRPoint(x: 1000, y: 2000),
                transform: .identity,
                properties: []
            ))
        ])
        let lib = IRLibrary(
            name: "PLCTEST",
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
            cells: [child, parent]
        )
        let data = try OASISLibraryWriter.write(lib)
        #expect(data.count > 0)
    }
}

// MARK: - Step 10-11: OASISLibraryReader Round-Trip

@Suite("OASISLibraryReader")
struct OASISLibraryReaderTests {

    @Test func readMinimalLibrary() throws {
        let lib = IRLibrary(
            name: "EMPTY",
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
            cells: [IRCell(name: "TOP")]
        )
        let data = try OASISLibraryWriter.write(lib)
        let result = try OASISLibraryReader.read(data)
        #expect(result.name == "EMPTY")
        #expect(result.cells.count == 1)
        #expect(result.cells[0].name == "TOP")
        #expect(result.cells[0].elements.isEmpty)
    }

    @Test func readRejectsInvalidUnitScale() throws {
        var writer = OASISWriter()
        writer.writeMagic()
        writer.writeByte(OASISRecordType.start.rawValue)
        try writer.writeAString("1.0")
        writer.writeReal(0)
        writer.writeUnsignedInteger(0)
        writer.writeByte(OASISRecordType.end.rawValue)
        try writer.writeAString("")
        writer.writeUnsignedInteger(0)

        do {
            _ = try OASISLibraryReader.read(writer.data)
            Issue.record("Expected invalid OASIS unit scale to throw")
        } catch let error as OASISError {
            guard case .invalidUnits(_, let reason) = error else {
                Issue.record("Expected OASISError.invalidUnits, got \(error)")
                return
            }
            #expect(reason.contains("greater than zero"))
        }
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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
            cells: [IRCell(name: "RECT", elements: [.boundary(boundary)])]
        )
        let data = try OASISLibraryWriter.write(original)
        let result = try OASISLibraryReader.read(data)

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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
            cells: [IRCell(name: "WIRE", elements: [.path(path)])]
        )
        let data = try OASISLibraryWriter.write(original)
        let result = try OASISLibraryReader.read(data)

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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
            cells: [IRCell(name: "LABEL", elements: [.text(text)])]
        )
        let data = try OASISLibraryWriter.write(original)
        let result = try OASISLibraryReader.read(data)

        if case .text(let t) = result.cells[0].elements[0] {
            #expect(t.layer == 6)
            #expect(t.texttype == 1)
            #expect(t.string == "GND")
            #expect(t.position == IRPoint(x: 500, y: 500))
        } else {
            Issue.record("Expected text element")
        }
    }

    @Test func readPlacementRoundTrip() throws {
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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
            cells: [child, parent]
        )
        let data = try OASISLibraryWriter.write(original)
        let result = try OASISLibraryReader.read(data)

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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
            cells: [cell]
        )
        let data = try OASISLibraryWriter.write(original)
        let result = try OASISLibraryReader.read(data)

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

    @Test func readUnitsRoundTrip() throws {
        let databaseUnitScale = try DatabaseUnitScale(databaseUnitsPerMicrometer: 100)
        let original = IRLibrary(
            name: "ULIB",
            databaseUnitScale: databaseUnitScale,
            cells: [IRCell(name: "A")]
        )
        let data = try OASISLibraryWriter.write(original)
        let result = try OASISLibraryReader.read(data)

        let relError = abs(result.databaseUnitScale.databaseUnitsPerMicrometer - 100.0) / 100.0
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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
            cells: [cell]
        )
        let data = try OASISLibraryWriter.write(original)
        let result = try OASISLibraryReader.read(data)

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

    @Test func readRectangleOptimization() throws {
        // Axis-aligned rectangle with 5 points should use RECTANGLE record
        let boundary = IRBoundary(
            layer: 1,
            datatype: 0,
            points: [
                IRPoint(x: 100, y: 200),
                IRPoint(x: 600, y: 200),
                IRPoint(x: 600, y: 700),
                IRPoint(x: 100, y: 700),
                IRPoint(x: 100, y: 200),
            ],
            properties: []
        )
        let original = IRLibrary(
            name: "RECTOPT",
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
            cells: [IRCell(name: "R", elements: [.boundary(boundary)])]
        )
        let data = try OASISLibraryWriter.write(original)
        let result = try OASISLibraryReader.read(data)

        if case .boundary(let b) = result.cells[0].elements[0] {
            #expect(b.layer == 1)
            #expect(b.points.count == 5)
            #expect(b.points[0] == IRPoint(x: 100, y: 200))
            #expect(b.points[2] == IRPoint(x: 600, y: 700))
        } else {
            Issue.record("Expected boundary element")
        }
    }
}
