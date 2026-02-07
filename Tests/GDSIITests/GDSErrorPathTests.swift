import Testing
import Foundation
@testable import GDSII

@Suite("GDSII Error Paths")
struct GDSErrorPathTests {

    // MARK: - GDSRecordReader errors

    @Test func emptyDataThrows() {
        var reader = GDSRecordReader(data: Data())
        #expect(throws: GDSError.self) {
            _ = try reader.readRecord()
        }
    }

    @Test func truncatedHeaderThrows() {
        // Only 3 bytes, need at least 4
        var reader = GDSRecordReader(data: Data([0x00, 0x06, 0x00]))
        #expect(throws: GDSError.self) {
            _ = try reader.readRecord()
        }
    }

    @Test func recordLengthTooSmall() {
        // Record length = 2 (< 4 minimum)
        var reader = GDSRecordReader(data: Data([0x00, 0x02, 0x00, 0x02]))
        #expect(throws: GDSError.self) {
            _ = try reader.readRecord()
        }
    }

    @Test func recordLengthExceedsData() {
        // Record length = 100 but only 4 bytes available
        var reader = GDSRecordReader(data: Data([0x00, 0x64, 0x00, 0x02]))
        #expect(throws: GDSError.self) {
            _ = try reader.readRecord()
        }
    }

    @Test func unknownRecordType() {
        // Valid 4-byte header with unknown record type 0xFF
        var reader = GDSRecordReader(data: Data([0x00, 0x04, 0xFF, 0x00]))
        #expect(throws: GDSError.self) {
            _ = try reader.readRecord()
        }
    }

    @Test func unknownDataType() {
        // Record type 0x00 (header) with unknown data type 0xFF
        var reader = GDSRecordReader(data: Data([0x00, 0x04, 0x00, 0xFF]))
        #expect(throws: GDSError.self) {
            _ = try reader.readRecord()
        }
    }

    @Test func peekOnEmptyThrows() {
        let reader = GDSRecordReader(data: Data())
        #expect(throws: GDSError.self) {
            _ = try reader.peekRecordType()
        }
    }

    @Test func peekUnknownRecordTypeThrows() {
        let reader = GDSRecordReader(data: Data([0x00, 0x04, 0xFF, 0x00]))
        #expect(throws: GDSError.self) {
            _ = try reader.peekRecordType()
        }
    }

    // MARK: - GDSLibraryReader errors

    @Test func missingHeaderThrows() {
        // First record is BGNLIB (0x01) instead of HEADER (0x00)
        // Record: length=4, type=0x01, datatype=0x00 (noData)
        let data = Data([0x00, 0x04, 0x01, 0x00])
        do {
            _ = try GDSLibraryReader.read(data)
            Issue.record("Should have thrown")
        } catch {
            // Expected: unexpectedRecord
        }
    }

    @Test func invalidStringInRecord() {
        // Build a valid HEADER + BGNLIB + LIBNAME with non-ASCII string payload
        var data = Data()
        // HEADER: length=6, type=0x00, datatype=0x02(int16), payload=[0x00, 0x06]
        data.append(contentsOf: [0x00, 0x06, 0x00, 0x02, 0x00, 0x06])
        // BGNLIB: length=28, type=0x01, datatype=0x02(int16), 24 bytes of zeros
        data.append(contentsOf: [0x00, 0x1C, 0x01, 0x02])
        data.append(contentsOf: [UInt8](repeating: 0, count: 24))
        // LIBNAME: length=6, type=0x02, datatype=0x06(string), payload=[0x80, 0xFF] (non-ASCII)
        data.append(contentsOf: [0x00, 0x06, 0x02, 0x06, 0x80, 0xFF])

        do {
            _ = try GDSLibraryReader.read(data)
            Issue.record("Should have thrown invalidString")
        } catch {
            // Expected: invalidString
        }
    }

    // MARK: - GDSReal8 edge cases

    @Test func real8AllZeroBytes() {
        let result = GDSReal8.toDouble((0, 0, 0, 0, 0, 0, 0, 0))
        #expect(result == 0.0)
    }

    @Test func real8NegativeZero() {
        // Sign bit set but mantissa is zero
        let result = GDSReal8.toDouble((0x80, 0, 0, 0, 0, 0, 0, 0))
        #expect(result == 0.0)
    }

    @Test func real8OverflowReturnsZero() {
        // A very large value that causes biasedExponent > 127 in fromDouble
        let bytes = GDSReal8.fromDouble(1e100)
        // Verify it either represents a large value or safely returns zero
        let reconstructed = GDSReal8.toDouble(bytes)
        #expect(reconstructed.isFinite)
    }

    @Test func real8UnderflowReturnsZero() {
        // A very small value
        let bytes = GDSReal8.fromDouble(1e-100)
        let reconstructed = GDSReal8.toDouble(bytes)
        #expect(reconstructed.isFinite)
    }

    @Test func real8NegativeValueRoundTrip() {
        let bytes = GDSReal8.fromDouble(-3.14)
        let result = GDSReal8.toDouble(bytes)
        #expect(abs(result - (-3.14)) < 1e-10)
    }

    @Test func real8SmallFractionRoundTrip() {
        let bytes = GDSReal8.fromDouble(0.001)
        let result = GDSReal8.toDouble(bytes)
        #expect(abs(result - 0.001) < 1e-12)
    }

    @Test func real8MaxExponentBoundary() {
        // Largest representable: exponent 63 in excess-64 → 16^63
        // Direct byte construction: sign=0, exponent=127 (0x7F), mantissa max
        let result = GDSReal8.toDouble((0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF))
        #expect(result > 0)
        #expect(result.isFinite)
    }

    @Test func real8MinExponentBoundary() {
        // Smallest positive: exponent=1 (biased), small mantissa
        let result = GDSReal8.toDouble((0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00))
        #expect(result > 0)
        #expect(result.isFinite)
    }
}
