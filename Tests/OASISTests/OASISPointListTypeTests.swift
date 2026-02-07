import Testing
import Foundation
import LayoutIR
@testable import OASIS

/// Tests for OASIS point list types 0-3 (Manhattan and Octangular).
/// Type 4 (general) is already covered by existing tests.
@Suite("OASIS Point List Types 0-3")
struct OASISPointListTypeTests {

    // MARK: - Helpers

    /// Builds binary data for a point list by writing typeCode, count, and encoded deltas.
    private func buildPointListData(
        typeCode: UInt64,
        signedDeltas: [Int64]
    ) -> Data {
        var writer = OASISWriter()
        writer.writeUnsignedInteger(typeCode)
        writer.writeUnsignedInteger(UInt64(signedDeltas.count))
        for d in signedDeltas {
            writer.writeSignedInteger(d)
        }
        return writer.data
    }

    private func buildPointListDataUnsigned(
        typeCode: UInt64,
        unsignedDeltas: [UInt64]
    ) -> Data {
        var writer = OASISWriter()
        writer.writeUnsignedInteger(typeCode)
        writer.writeUnsignedInteger(UInt64(unsignedDeltas.count))
        for d in unsignedDeltas {
            writer.writeUnsignedInteger(d)
        }
        return writer.data
    }

    // MARK: - Type 0: Manhattan, horizontal-first

    @Test func manhattanHFirstBasic() throws {
        // 4 deltas: H(+100), V(+50), H(-100), V(-50)
        let data = buildPointListData(typeCode: 0, signedDeltas: [100, 50, -100, -50])
        var reader = OASISReader(data: data)
        let points = try reader.readPointList()
        #expect(points == [
            IRPoint(x: 100, y: 0),   // even index → horizontal
            IRPoint(x: 0, y: 50),    // odd index → vertical
            IRPoint(x: -100, y: 0),  // even → horizontal
            IRPoint(x: 0, y: -50),   // odd → vertical
        ])
    }

    @Test func manhattanHFirstSingleDelta() throws {
        let data = buildPointListData(typeCode: 0, signedDeltas: [42])
        var reader = OASISReader(data: data)
        let points = try reader.readPointList()
        #expect(points == [IRPoint(x: 42, y: 0)])
    }

    @Test func manhattanHFirstEmpty() throws {
        let data = buildPointListData(typeCode: 0, signedDeltas: [])
        var reader = OASISReader(data: data)
        let points = try reader.readPointList()
        #expect(points.isEmpty)
    }

    // MARK: - Type 1: Manhattan, vertical-first

    @Test func manhattanVFirstBasic() throws {
        // 4 deltas: V(+50), H(+100), V(-50), H(-100)
        let data = buildPointListData(typeCode: 1, signedDeltas: [50, 100, -50, -100])
        var reader = OASISReader(data: data)
        let points = try reader.readPointList()
        #expect(points == [
            IRPoint(x: 0, y: 50),    // even index → vertical
            IRPoint(x: 100, y: 0),   // odd index → horizontal
            IRPoint(x: 0, y: -50),   // even → vertical
            IRPoint(x: -100, y: 0),  // odd → horizontal
        ])
    }

    @Test func manhattanVFirstSingleDelta() throws {
        let data = buildPointListData(typeCode: 1, signedDeltas: [-77])
        var reader = OASISReader(data: data)
        let points = try reader.readPointList()
        #expect(points == [IRPoint(x: 0, y: -77)])
    }

    // MARK: - Type 2: Manhattan, any-direction

    @Test func manhattanAnyAllFourDirections() throws {
        // Encoding: (magnitude << 2) | direction
        // dir 0=east, 1=north, 2=west, 3=south
        let encoded: [UInt64] = [
            (100 << 2) | 0, // east  +100
            (50  << 2) | 1, // north +50
            (100 << 2) | 2, // west  -100
            (50  << 2) | 3, // south -50
        ]
        let data = buildPointListDataUnsigned(typeCode: 2, unsignedDeltas: encoded)
        var reader = OASISReader(data: data)
        let points = try reader.readPointList()
        #expect(points == [
            IRPoint(x: 100, y: 0),
            IRPoint(x: 0, y: 50),
            IRPoint(x: -100, y: 0),
            IRPoint(x: 0, y: -50),
        ])
    }

    @Test func manhattanAnySingleDelta() throws {
        let encoded: [UInt64] = [(200 << 2) | 3] // south 200
        let data = buildPointListDataUnsigned(typeCode: 2, unsignedDeltas: encoded)
        var reader = OASISReader(data: data)
        let points = try reader.readPointList()
        #expect(points == [IRPoint(x: 0, y: -200)])
    }

    // MARK: - Type 3: Octangular

    @Test func octangularAllEightDirections() throws {
        // Encoding: (magnitude << 3) | direction
        // 0=E, 1=N, 2=W, 3=S, 4=NE, 5=NW, 6=SE, 7=SW
        let mag: UInt64 = 10
        let encoded: [UInt64] = [
            (mag << 3) | 0, // east
            (mag << 3) | 1, // north
            (mag << 3) | 2, // west
            (mag << 3) | 3, // south
            (mag << 3) | 4, // NE
            (mag << 3) | 5, // NW
            (mag << 3) | 6, // SE
            (mag << 3) | 7, // SW
        ]
        let data = buildPointListDataUnsigned(typeCode: 3, unsignedDeltas: encoded)
        var reader = OASISReader(data: data)
        let points = try reader.readPointList()
        #expect(points == [
            IRPoint(x: 10, y: 0),     // E
            IRPoint(x: 0, y: 10),     // N
            IRPoint(x: -10, y: 0),    // W
            IRPoint(x: 0, y: -10),    // S
            IRPoint(x: 10, y: 10),    // NE
            IRPoint(x: -10, y: 10),   // NW
            IRPoint(x: 10, y: -10),   // SE
            IRPoint(x: -10, y: -10),  // SW
        ])
    }

    @Test func octangularLargeMagnitude() throws {
        let mag: UInt64 = 5000
        let encoded: [UInt64] = [
            (mag << 3) | 4, // NE
            (mag << 3) | 7, // SW
        ]
        let data = buildPointListDataUnsigned(typeCode: 3, unsignedDeltas: encoded)
        var reader = OASISReader(data: data)
        let points = try reader.readPointList()
        #expect(points == [
            IRPoint(x: 5000, y: 5000),
            IRPoint(x: -5000, y: -5000),
        ])
    }

    // MARK: - Invalid type

    @Test func invalidPointListTypeThrows() {
        let data = buildPointListDataUnsigned(typeCode: 99, unsignedDeltas: [])
        var reader = OASISReader(data: data)
        #expect(throws: OASISError.self) {
            _ = try reader.readPointList()
        }
    }
}
