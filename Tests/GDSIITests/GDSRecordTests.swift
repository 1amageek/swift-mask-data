import Testing
import Foundation
import LayoutIR
@testable import GDSII

@Suite("GDSRecordReader")
struct GDSRecordReaderTests {

    @Test func readHeaderRecord() throws {
        // HEADER record: length=6, type=0x00, dataType=0x02(int16), version=600 (0x0258)
        let bytes: [UInt8] = [0x00, 0x06, 0x00, 0x02, 0x02, 0x58]
        var reader = GDSRecordReader(data: Data(bytes))
        let record = try reader.readRecord()
        #expect(record.recordType == .header)
        if case .int16(let values) = record.payload {
            #expect(values == [600])
        } else {
            Issue.record("Expected int16 payload")
        }
        #expect(!reader.hasMore)
    }

    @Test func readEndlibRecord() throws {
        // ENDLIB: length=4, type=0x04, dataType=0x00
        let bytes: [UInt8] = [0x00, 0x04, 0x04, 0x00]
        var reader = GDSRecordReader(data: Data(bytes))
        let record = try reader.readRecord()
        #expect(record.recordType == .endlib)
        #expect(record.payload == .noData)
    }

    @Test func readStringRecord() throws {
        // LIBNAME: length=10, type=0x02, dataType=0x06, "TEST" + padding
        let bytes: [UInt8] = [0x00, 0x0A, 0x02, 0x06, 0x54, 0x45, 0x53, 0x54, 0x00, 0x00]
        var reader = GDSRecordReader(data: Data(bytes))
        let record = try reader.readRecord()
        #expect(record.recordType == .libname)
        if case .string(let s) = record.payload {
            #expect(s == "TEST")
        } else {
            Issue.record("Expected string payload")
        }
    }

    @Test func readLayerRecord() throws {
        // LAYER: length=6, type=0x0D, dataType=0x02, layer=30
        let bytes: [UInt8] = [0x00, 0x06, 0x0D, 0x02, 0x00, 0x1E]
        var reader = GDSRecordReader(data: Data(bytes))
        let record = try reader.readRecord()
        #expect(record.recordType == .layer)
        if case .int16(let values) = record.payload {
            #expect(values == [30])
        } else {
            Issue.record("Expected int16 payload")
        }
    }

    @Test func readMultipleRecords() throws {
        // Two records: ENDSTR + ENDLIB
        let bytes: [UInt8] = [
            0x00, 0x04, 0x07, 0x00,  // ENDSTR
            0x00, 0x04, 0x04, 0x00,  // ENDLIB
        ]
        var reader = GDSRecordReader(data: Data(bytes))
        let r1 = try reader.readRecord()
        let r2 = try reader.readRecord()
        #expect(r1.recordType == .endstr)
        #expect(r2.recordType == .endlib)
        #expect(!reader.hasMore)
    }

    @Test func peekRecordType() throws {
        let bytes: [UInt8] = [0x00, 0x04, 0x07, 0x00]
        let reader = GDSRecordReader(data: Data(bytes))
        let peeked = try reader.peekRecordType()
        #expect(peeked == .endstr)
        #expect(reader.hasMore)
    }

    @Test func emptyDataThrows() {
        var reader = GDSRecordReader(data: Data())
        #expect(throws: GDSError.self) {
            _ = try reader.readRecord()
        }
    }

    @Test func truncatedDataThrows() {
        let bytes: [UInt8] = [0x00, 0x10, 0x00, 0x02]  // claims 16 bytes but only 4
        var reader = GDSRecordReader(data: Data(bytes))
        #expect(throws: GDSError.self) {
            _ = try reader.readRecord()
        }
    }
}

@Suite("GDSRecordWriter")
struct GDSRecordWriterTests {

    @Test func writeNoData() {
        var writer = GDSRecordWriter()
        writer.writeNoData(.endlib)
        let bytes = Array(writer.data)
        #expect(bytes == [0x00, 0x04, 0x04, 0x00])
    }

    @Test func writeInt16() {
        var writer = GDSRecordWriter()
        writer.writeInt16(.header, values: [600])
        let bytes = Array(writer.data)
        #expect(bytes == [0x00, 0x06, 0x00, 0x02, 0x02, 0x58])
    }

    @Test func writeString() {
        var writer = GDSRecordWriter()
        writer.writeString(.libname, value: "TEST")
        let bytes = Array(writer.data)
        // "TEST" = 4 bytes, even length, no padding needed
        #expect(bytes == [0x00, 0x08, 0x02, 0x06, 0x54, 0x45, 0x53, 0x54])
    }

    @Test func writeStringOddLength() {
        var writer = GDSRecordWriter()
        writer.writeString(.libname, value: "AB")
        let bytes = Array(writer.data)
        // "AB" = 2 bytes, even, total = 6
        #expect(bytes == [0x00, 0x06, 0x02, 0x06, 0x41, 0x42])
    }

    @Test func writeStringOddPadding() {
        var writer = GDSRecordWriter()
        writer.writeString(.libname, value: "ABC")
        let bytes = Array(writer.data)
        // "ABC" = 3 bytes, padded to 4 bytes, total = 8
        #expect(bytes == [0x00, 0x08, 0x02, 0x06, 0x41, 0x42, 0x43, 0x00])
    }

    @Test func writeXY() {
        var writer = GDSRecordWriter()
        writer.writeXY([IRPoint(x: 100, y: -200)])
        let bytes = Array(writer.data)
        // XY: type=0x10, dataType=0x03, 2 int32s = 8 bytes payload, total=12
        #expect(bytes.count == 12)
        #expect(bytes[2] == 0x10) // XY record type
        #expect(bytes[3] == 0x03) // Int32 data type
    }

    @Test func writeReadRoundTrip() throws {
        var writer = GDSRecordWriter()
        writer.writeInt16(.header, values: [600])
        writer.writeString(.libname, value: "MYLIB")
        writer.writeNoData(.endlib)

        var reader = GDSRecordReader(data: writer.data)
        let r1 = try reader.readRecord()
        let r2 = try reader.readRecord()
        let r3 = try reader.readRecord()

        #expect(r1.recordType == .header)
        #expect(r2.recordType == .libname)
        if case .string(let s) = r2.payload {
            #expect(s == "MYLIB")
        }
        #expect(r3.recordType == .endlib)
        #expect(!reader.hasMore)
    }
}
