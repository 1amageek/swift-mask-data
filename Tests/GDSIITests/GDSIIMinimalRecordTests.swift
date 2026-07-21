import Foundation
import Testing
@testable import GDSII

@Suite("GDSII Minimal Record Validation")
struct GDSIIMinimalRecordTests {
    @Test func truncatedHeaderFailsAtRecordBoundary() {
        var reader = GDSRecordReader(data: Data([0x00, 0x06, 0x00]))
        #expect(throws: GDSError.self) {
            _ = try reader.readRecord()
        }
    }

    @Test func headerRecordDecodesVersion() throws {
        var reader = GDSRecordReader(data: Data([0x00, 0x06, 0x00, 0x02, 0x00, 0x06]))
        let record = try reader.readRecord()
        #expect(record.recordType == .header)
        #expect(record.payload == .int16([6]))
    }
}
