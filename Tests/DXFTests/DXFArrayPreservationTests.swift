import CircuiteFoundation
import DXF
import Foundation
import LayoutIR
import Testing

@Suite("DXF array preservation")
struct DXFArrayPreservationTests {
    @Test func literalRotatedGridUsesBothAxesAndDoesNotScaleOffsets() throws {
        let bytes = Data("""
        0
        SECTION
        2
        BLOCKS
        0
        BLOCK
        2
        CHILD
        0
        ENDBLK
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        INSERT
        2
        CHILD
        10
        1
        20
        2
        41
        2
        42
        2
        50
        90
        70
        3
        71
        2
        44
        10
        45
        20
        0
        ENDSEC
        0
        EOF
        """.utf8)
        let library = try DXFLibraryReader.read(bytes, databaseUnitScale: scale())
        let array = try #require(library.cells.flatMap(\.elements).compactMap { element -> IRArrayRef? in
            if case .arrayRef(let array) = element { return array }
            return nil
        }.first)
        #expect(array.referencePoints == [IRPoint(x: 1000, y: 2000), IRPoint(x: 1000, y: 32000), IRPoint(x: -39000, y: 2000)])
        #expect(array.transform.magnification == 2)
    }

    @Test func rotatedArrayRoundTripAndSkewRefusal() throws {
        let array = IRArrayRef(cellName: "CHILD", transform: IRTransform(angle: 90), columns: 3, rows: 2,
            referencePoints: [IRPoint(x: 1000, y: 2000), IRPoint(x: 1000, y: 32000), IRPoint(x: -39000, y: 2000)])
        let bytes = try DXFLibraryWriter.write(library(array: array))
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(text.contains(" 44\n10.0\n"))
        #expect(text.contains(" 45\n20.0\n"))
        let result = try DXFLibraryReader.read(bytes, databaseUnitScale: scale())
        #expect(result.cells[0].elements == [.arrayRef(array)])
        var skew = array
        skew.referencePoints[1].x += 1
        #expect(throws: DXFError.self) { _ = try DXFLibraryWriter.write(library(array: skew)) }
    }

    @Test func fullInt32SpanAndFractionalSpacingRetainExactEndpoints() throws {
        for endpoint in [Int32.max, Int32(-2147483548)] {
            let array = IRArrayRef(cellName: "CHILD", columns: 3, rows: 2,
                referencePoints: [IRPoint(x: .min, y: 0), IRPoint(x: endpoint, y: 0), IRPoint(x: .min, y: 2000)])
            let bytes = try DXFLibraryWriter.write(library(array: array))
            let result = try DXFLibraryReader.read(bytes, databaseUnitScale: scale())
            #expect(result.cells[0].elements == [.arrayRef(array)])
        }
    }

    @Test func mirroredArrayPreservesStandardNegativeXAction() throws {
        let array = IRArrayRef(cellName: "CHILD", transform: IRTransform(mirrorX: true, magnification: 2, angle: 180),
            columns: 2, rows: 2,
            referencePoints: [IRPoint(x: 0, y: 0), IRPoint(x: 2000, y: 0), IRPoint(x: 0, y: 4000)])
        let bytes = try DXFLibraryWriter.write(library(array: array))
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(text.contains(" 41\n-2.0\n"))
        #expect(!text.contains(" 50\n180.0\n"))
        let result = try DXFLibraryReader.read(bytes, databaseUnitScale: scale())
        #expect(result.cells[0].elements == [.arrayRef(array)])
        // Reflection about X followed by a half-turn maps (2, 3) to (-2, 3).
        #expect(array.transform.mirrorX && array.transform.angle == 180)
    }

    @Test func smallSourceCoordinatesAndNearUnitPoseAreNotQuantizedByWriter() throws {
        let scale = try DatabaseUnitScale(databaseUnitsPerMicrometer: 1_000_000_000)
        let reference = IRCellRef(cellName: "CHILD", origin: IRPoint(x: 1, y: -3),
            transform: IRTransform(magnification: 1.0000000001, angle: 0.0000000001))
        let source = IRLibrary(name: "PRESERVE", databaseUnitScale: scale,
            cells: [IRCell(name: "TOP", elements: [.cellRef(reference)]), IRCell(name: "CHILD")])
        let result = try DXFLibraryReader.read(DXFLibraryWriter.write(source), databaseUnitScale: scale)
        #expect(result.cells[0].elements == source.cells[0].elements)
    }

    @Test func decimalDBUNoiseDoesNotChangeExactCoordinatesOrFractionalTruncation() throws {
        let references = [1001, -1001].map { x in
            IRElement.cellRef(IRCellRef(cellName: "CHILD", origin: IRPoint(x: Int32(x), y: 0)))
        }
        let source = IRLibrary(name: "PRESERVE", databaseUnitScale: try scale(),
            cells: [IRCell(name: "TOP", elements: references), IRCell(name: "CHILD")])
        let bytes = try DXFLibraryWriter.write(source)
        let result = try DXFLibraryReader.read(bytes, databaseUnitScale: scale())
        #expect(result.cells[0].elements == references)
        let fractional = Data(String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "1.001\n", with: "1.0019\n").utf8)
        let quantized = try DXFLibraryReader.read(fractional, databaseUnitScale: scale())
        #expect(quantized.cells[0].elements == references)
    }

    private func scale() throws -> DatabaseUnitScale { try DatabaseUnitScale(databaseUnitsPerMicrometer: 1000) }
    private func library(array: IRArrayRef) throws -> IRLibrary {
        IRLibrary(name: "PRESERVE", databaseUnitScale: try scale(),
            cells: [IRCell(name: "TOP", elements: [.arrayRef(array)]), IRCell(name: "CHILD")])
    }
}
