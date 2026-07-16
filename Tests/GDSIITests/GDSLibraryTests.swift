import CircuiteFoundation
import Testing
import Foundation
import LayoutIR
@testable import GDSII

@Suite("GDSLibraryWriter")
struct GDSLibraryWriterTests {

    @Test func writeMinimalLibrary() throws {
        let lib = IRLibrary(
            name: "EMPTY",
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
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
        let databaseUnitScale = try DatabaseUnitScale(databaseUnitsPerMicrometer: 100)
        let original = IRLibrary(
            name: "ULIB",
            databaseUnitScale: databaseUnitScale,
            cells: [IRCell(name: "A")]
        )
        let data = try GDSLibraryWriter.write(original)
        let result = try GDSLibraryReader.read(data)

        let relError = abs(result.databaseUnitScale.databaseUnitsPerMicrometer - 100.0) / 100.0
        #expect(relError < 1e-6)
    }

    @Test func readUnitsUsesUserUnitsPerDBU() throws {
        var writer = GDSRecordWriter()
        try writer.writeInt16(.header, values: [600])
        try writer.writeInt16(.bgnlib, values: Array(repeating: 0, count: 12))
        try writer.writeString(.libname, value: "UNITS")
        try writer.writeReal8(.units, values: [0.002, 1e-9])
        try writer.writeNoData(.endlib)

        let result = try GDSLibraryReader.read(writer.data)
        #expect(abs(result.databaseUnitScale.databaseUnitsPerMicrometer - 500.0) < 1e-6)
    }

    @Test func readUnitsRejectsInvalidScaleInsteadOfUsingDefault() throws {
        var writer = GDSRecordWriter()
        try writer.writeInt16(.header, values: [600])
        try writer.writeInt16(.bgnlib, values: Array(repeating: 0, count: 12))
        try writer.writeString(.libname, value: "INVALID_UNITS")
        try writer.writeReal8(.units, values: [0, 0])
        try writer.writeNoData(.endlib)

        do {
            _ = try GDSLibraryReader.read(writer.data)
            Issue.record("Expected invalid UNITS to throw")
        } catch let error as GDSError {
            guard case .invalidUnits(_, let context) = error else {
                Issue.record("Expected GDSError.invalidUnits, got \(error)")
                return
            }
            #expect(context.contains("positive"))
        }
    }

    @Test func readWritePreservesGDSTimestamps() throws {
        let libraryCreatedAt = IRDateTime(year: 2024, month: 2, day: 3, hour: 4, minute: 5, second: 6)
        let libraryModifiedAt = IRDateTime(year: 2025, month: 7, day: 8, hour: 9, minute: 10, second: 11)
        let cellCreatedAt = IRDateTime(year: 2023, month: 1, day: 2, hour: 3, minute: 4, second: 5)
        let cellModifiedAt = IRDateTime(year: 2026, month: 6, day: 7, hour: 8, minute: 9, second: 10)
        let original = IRLibrary(
            name: "TIMELIB",
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
            cells: [
                IRCell(
                    name: "TOP",
                    createdAt: cellCreatedAt,
                    modifiedAt: cellModifiedAt
                )
            ],
            createdAt: libraryCreatedAt,
            modifiedAt: libraryModifiedAt
        )

        let data = try GDSLibraryWriter.write(original)
        let result = try GDSLibraryReader.read(data)
        let rewritten = try GDSLibraryWriter.write(result)

        #expect(result.createdAt == libraryCreatedAt)
        #expect(result.modifiedAt == libraryModifiedAt)
        #expect(result.cells.first?.createdAt == cellCreatedAt)
        #expect(result.cells.first?.modifiedAt == cellModifiedAt)
        #expect(rewritten == data)
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
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000),
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
