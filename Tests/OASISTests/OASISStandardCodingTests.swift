import Foundation
import Testing
import LayoutIR
import CircuiteFoundation
@testable import OASIS

@Suite("Standard OASIS coding")
struct OASISStandardCodingTests {
    @Test func literalSignedIntegersUseMagnitude() throws {
        for (bytes, value) in [([UInt8(3)], Int64(-1)), ([21], -10), ([1], 0)] {
            var reader = OASISReader(data: Data(bytes))
            #expect(try reader.readSignedInteger() == value)
        }
        var writer = OASISWriter()
        writer.writeSignedInteger(-1)
        writer.writeSignedInteger(-10)
        #expect(writer.data == Data([3, 21]))
    }

    @Test func literalGeneralAndOctangularDeltas() throws {
        var general = OASISReader(data: Data([4, 1, 15, 4]))
        #expect(try general.readPointList() == [IRPoint(x: -3, y: 2)])
        var octangular = OASISReader(data: Data([3, 2, 30, 31]))
        #expect(try octangular.readPointList() == [IRPoint(x: -3, y: -3), IRPoint(x: 3, y: -3)])
        var writer = OASISWriter()
        writer.writePointList([IRPoint(x: -3, y: 2)])
        #expect(writer.data == Data([4, 1, 15, 4]))
    }

    @Test func literalStandardPathPreservesBothSignedExtensionsAndUnits() throws {
        // START 1.0, integer unit 1000, tables in START, inline cell C.
        var data = Data("%SEMI-OASIS\r\n".utf8)
        data.append(contentsOf: [1, 3, 49, 46, 48, 0, 232, 7, 0])
        data.append(Data(repeating: 0, count: 12))
        data.append(contentsOf: [14, 1, 67, 22, 251, 1, 0, 2, 15, 6, 3, 0, 1, 20, 11, 14])
        data.append(Self.endRecord(tables: false))
        let library = try OASISLibraryReader.read(data)
        #expect(library.databaseUnitScale.databaseUnitsPerMicrometer == 1000)
        let element = try #require(library.cells.first?.elements.first)
        guard case .path(let path) = element else { Issue.record("Expected PATH"); return }
        #expect(path.beginExtension == 3)
        #expect(path.endExtension == -1)
        #expect(path.points == [IRPoint(x: -5, y: 7), IRPoint(x: 5, y: 7)])
    }

    @Test func signedBoundaryBytesAndFailures() throws {
        let minimumBytes = Data([129] + Array(repeating: UInt8(128), count: 8) + [2])
        var reader = OASISReader(data: minimumBytes)
        #expect(try reader.readSignedInteger() == Int64.min)
        var writer = OASISWriter()
        writer.writeSignedInteger(Int64.min)
        #expect(writer.data == minimumBytes)
        for value in [Int64.max, Int64.min + 1] {
            var writer = OASISWriter()
            writer.writeSignedInteger(value)
            var reader = OASISReader(data: writer.data)
            #expect(try reader.readSignedInteger() == value)
        }
        for bytes in [Data([128]), Data([128] + Array(repeating: UInt8(128), count: 8) + [2]), Data([129] + Array(repeating: UInt8(128), count: 8) + [4])] {
            var reader = OASISReader(data: bytes)
            #expect(throws: OASISError.self) { _ = try reader.readSignedInteger() }
        }
    }

    @Test func everyExtensionSchemeResolvesBothEndpoints() throws {
        for scheme: UInt8 in 0...15 {
            var records: [UInt8] = [22, 251, 1, 0, 2, 15, 6, 3, 0, 1, 20, 0, 0]
            records += [22, 192, 4, scheme]
            if scheme >> 2 == 3 { records += [10] }
            if scheme & 3 == 3 { records += [5] }
            let paths = try Self.paths(records)
            let begin = [3, 0, 4, 5][Int(scheme >> 2)]
            let end = [-1, 0, 4, -2][Int(scheme & 3)]
            let path = try #require(paths.last)
            let actual = Self.extensions(path)
            #expect(actual.0 == begin)
            #expect(actual.1 == end)
            #expect(path.width == 8)
            #expect(path.points == [IRPoint(x: 0, y: 0), IRPoint(x: 10, y: 0)])
        }
    }

    @Test func omittedExtensionsRetainResolvedValuesAfterWidthChange() throws {
        let records: [UInt8] = [22, 251, 1, 0, 2, 10, 0, 1, 20, 0, 0, 22, 64, 4]
        let paths = try Self.paths(records)
        #expect(paths[0].pathType == .halfWidthExtend)
        #expect(paths[1].pathType == .customExtension)
        #expect(paths[1].beginExtension == 2)
        #expect(paths[1].endExtension == 2)
    }

    @Test func explicitZeroAndHalfWidthKeepCustomIntent() throws {
        let paths = try Self.paths([22, 251, 1, 0, 2, 15, 0, 4, 0, 1, 20, 0, 0, 22, 0])
        #expect(paths.allSatisfy { $0.pathType == .customExtension && $0.beginExtension == 0 && $0.endExtension == 2 })
    }

    @Test func relativeOriginsAreIndependentAcrossRecordFamilies() throws {
        // Geometry origin (10,20); text (100,100); placement (30,40).
        // Then relative text (+1,+2), placement (+3,+4), geometry (-5,+7).
        let records: [UInt8] = [
            22, 251, 1, 0, 2, 5, 0, 1, 20, 20, 40,
            19, 91, 1, 84, 1, 0, 200, 1, 200, 1,
            17, 176, 1, 67, 60, 80,
            16, 19, 24, 2, 4, 17, 48, 6, 8, 22, 24, 11, 14,
            15, 22, 16, 18
        ]
        let lib = try OASISLibraryReader.read(Self.libraryBytes(records))
        let elements = lib.cells[0].elements
        guard case .text(let text) = elements[3], case .cellRef(let placement) = elements[4] else {
            Issue.record("Expected independent text/placement records"); return
        }
        #expect(text.position == IRPoint(x: 101, y: 102))
        #expect(placement.origin == IRPoint(x: 33, y: 44))
        let paths = elements.compactMap { if case .path(let p) = $0 { p } else { nil } }
        #expect(paths[1].points[0] == IRPoint(x: 5, y: 27))
        #expect(paths[2].points[0] == IRPoint(x: 9, y: 27))
    }

    @Test func undefinedInvalidAndOverflowingPathsFail() {
        let badRecords: [[UInt8]] = [
            [22, 0],
            [22, 251, 1, 0, 2, 16],
            [22, 251, 1, 0, 2, 0],
            [22, 251, 1, 0, 2, 15, 128],
            [22, 219, 1, 0, 2, 5, 0, 0],
            [22, 251, 1, 0, 0, 5, 0, 1, 20, 0, 0],
            [22, 251, 1, 0, 128, 128, 128, 128, 4, 5, 0, 1, 20, 0, 0],
            [22, 251, 1, 0, 2, 15, 128, 128, 128, 128, 16, 0, 0, 1, 20, 0, 0]
        ]
        for bytes in badRecords {
            #expect(throws: OASISError.self) { _ = try OASISLibraryReader.read(Self.libraryBytes(bytes)) }
        }
        let seeded: [UInt8] = [22, 251, 1, 0, 2, 5, 0, 1, 20, 0, 0]
        #expect(throws: OASISError.self) {
            _ = try OASISLibraryReader.read(Self.libraryBytes(seeded + [14, 1, 68, 22, 0]))
        }
    }

    @Test func standardEnvelopePlacementAndMalformedEnd() throws {
        for tablesAtEnd in [false, true] {
            let lib = try OASISLibraryReader.read(Self.libraryBytes([], tablesAtEnd: tablesAtEnd))
            #expect(lib.databaseUnitScale.databaseUnitsPerMicrometer == 1000)
        }
        var missing = Self.libraryBytes([])
        missing.removeLast(256)
        #expect(throws: OASISError.self) { _ = try OASISLibraryReader.read(missing) }
        var short = Self.libraryBytes([])
        short.removeLast()
        #expect(throws: OASISError.self) { _ = try OASISLibraryReader.read(short) }
        var trailing = Self.libraryBytes([])
        trailing.append(0)
        #expect(throws: OASISError.self) { _ = try OASISLibraryReader.read(trailing) }
        var signed = Self.libraryBytes([])
        signed[signed.count - 1] = 1
        #expect(throws: OASISError.self) { _ = try OASISLibraryReader.read(signed) }
        var invalidFlag = Self.libraryBytes([], tablesAtEnd: true)
        invalidFlag[21] = 2
        #expect(throws: OASISError.self) { _ = try OASISLibraryReader.read(invalidFlag) }
    }

    @Test func customWriterUsesStandardBytesAndExportsOracleFixture() throws {
        let path = IRPath(layer: 1, datatype: 0, pathType: .customExtension, width: 4,
            points: [IRPoint(x: -5, y: 7), IRPoint(x: 5, y: 7)], properties: [IRProperty(attribute: 0, value: "net=signal")], beginExtension: 3, endExtension: -1)
        let lib = IRLibrary(name: "CUSTOM", databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1000),
            cells: [IRCell(name: "C", elements: [.path(path)])])
        let bytes = try OASISLibraryWriter.write(lib)
        #expect(bytes.suffix(256) == Self.endRecord(tables: true))
        #expect(bytes.range(of: Data([22, 251, 1, 0, 2, 15, 6, 3, 0, 1, 20, 11, 14])) != nil)
        var decoded = OASISReader(data: bytes)
        try decoded.validateMagic()
        #expect(try decoded.readByte() == 1)
        #expect(try decoded.readAString() == "1.0")
        #expect(try decoded.readReal() == 1000)
        #expect(try decoded.readUnsignedInteger() == 1)
        let roundTrip = try OASISLibraryReader.read(bytes)
        guard case .path(let restored) = roundTrip.cells[0].elements[0] else { Issue.record("Expected PATH"); return }
        #expect(restored.points == path.points)
        #expect(restored.beginExtension == path.beginExtension)
        #expect(restored.endExtension == path.endExtension)
        #expect(restored.properties.map(\.value) == ["net=signal"])
        if let directory = ProcessInfo.processInfo.environment["LSI_OASIS_EXPORT_EVIDENCE_DIRECTORY"] {
            try bytes.write(to: URL(fileURLWithPath: directory).appendingPathComponent("custom-path.oas"))
        }
    }

    @Test func customWriterRejectsMissingOrIgnoredEndpointFields() throws {
        let scale = try DatabaseUnitScale(databaseUnitsPerMicrometer: 1000)
        for path in [
            IRPath(layer: 1, datatype: 0, pathType: .customExtension, width: 4, points: [IRPoint(x: 0, y: 0), IRPoint(x: 10, y: 0)], beginExtension: 2),
            IRPath(layer: 1, datatype: 0, pathType: .flush, width: 4, points: [IRPoint(x: 0, y: 0), IRPoint(x: 10, y: 0)], beginExtension: 2)
        ] {
            #expect(throws: OASISError.self) {
                _ = try OASISLibraryWriter.write(IRLibrary(name: "C", databaseUnitScale: scale, cells: [IRCell(name: "C", elements: [.path(path)])]))
            }
        }
    }

    @Test func coincidentPathEndpointsRetainTheFinalSegment() throws {
        let points = [IRPoint(x: 0, y: 0), IRPoint(x: 10, y: 0), IRPoint(x: 10, y: 10), IRPoint(x: 0, y: 0)]
        let path = IRPath(layer: 1, datatype: 0, width: 4, points: points)
        let lib = IRLibrary(name: "C", databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1000), cells: [IRCell(name: "C", elements: [.path(path)])])
        let restored = try OASISLibraryReader.read(OASISLibraryWriter.write(lib))
        guard case .path(let result) = restored.cells[0].elements[0] else { Issue.record("Expected PATH"); return }
        #expect(result.points == points)
    }

    @Test func propertyScalarsUseStandardTypeCodes() throws {
        let examples: [(OASISPropertyValue, [UInt8])] = [
            (.real(3), [0, 3]), (.real(-0.5), [3, 2]),
            (.unsignedInteger(7), [8, 7]), (.signedInteger(-3), [9, 7]),
            (.aString("N"), [10, 1, 78]), (.bString([255]), [11, 1, 255])
        ]
        for (value, bytes) in examples {
            var writer = OASISWriter()
            try writer.writePropertyValue(value)
            #expect(writer.data == Data(bytes))
            var reader = OASISReader(data: Data(bytes))
            #expect(try reader.readPropertyValue() == value)
        }
        var invalid = OASISReader(data: Data([16]))
        #expect(throws: OASISError.self) { _ = try invalid.readPropertyValue() }
        let geometry: [UInt8] = [22, 251, 1, 0, 2, 5, 0, 1, 20, 0, 0]
        for type: UInt8 in [13, 14, 15] {
            #expect(throws: OASISError.self) {
                _ = try OASISLibraryReader.read(Self.libraryBytes(geometry + [28, 20, 1, 78, type, 0]))
            }
        }
    }

    @Test func minimumNegativeOctangularDeltaDoesNotTrap() throws {
        let points = [IRPoint(x: Int32.min, y: Int32.min), IRPoint(x: 3, y: -3)]
        var writer = OASISWriter()
        writer.writePointList(points)
        var reader = OASISReader(data: writer.data)
        #expect(try reader.readPointList() == points)
    }

    private static func extensions(_ path: IRPath) -> (Int, Int) {
        switch path.pathType {
        case .flush: return (0, 0)
        case .halfWidthExtend: return (Int(path.width / 2), Int(path.width / 2))
        default: return (Int(path.beginExtension ?? 0), Int(path.endExtension ?? 0))
        }
    }

    private static func paths(_ records: [UInt8]) throws -> [IRPath] {
        try OASISLibraryReader.read(libraryBytes(records)).cells[0].elements.compactMap {
            if case .path(let path) = $0 { path } else { nil }
        }
    }

    private static func libraryBytes(_ records: [UInt8], tablesAtEnd: Bool = false) -> Data {
        var data = Data("%SEMI-OASIS\r\n".utf8)
        data.append(contentsOf: [1, 3, 49, 46, 48, 0, 232, 7, tablesAtEnd ? 1 : 0])
        if !tablesAtEnd { data.append(Data(repeating: 0, count: 12)) }
        data.append(contentsOf: [14, 1, 67])
        data.append(contentsOf: records)
        data.append(endRecord(tables: tablesAtEnd))
        return data
    }

    static func endRecord(tables: Bool) -> Data {
        let padding = tables ? 240 : 252
        var result = Data([2])
        if tables { result.append(Data(repeating: 0, count: 12)) }
        result.append(contentsOf: [UInt8(padding & 127) | 128, UInt8(padding >> 7)])
        result.append(Data(repeating: 0, count: padding))
        result.append(0)
        return result
    }
}
