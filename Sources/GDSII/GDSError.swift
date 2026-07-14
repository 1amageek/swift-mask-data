public enum GDSError: Error, Sendable {
    case unexpectedEndOfData(offset: Int)
    case invalidRecordLength(offset: Int, length: UInt16)
    case unknownRecordType(offset: Int, rawValue: UInt8)
    case unknownDataType(offset: Int, rawValue: UInt8)
    case missingRequiredRecord(GDSRecordType, context: String)
    case unexpectedRecord(got: GDSRecordType, expected: GDSRecordType, offset: Int)
    case unsupportedRecord(recordType: GDSRecordType, context: String, offset: Int)
    case invalidUnits(offset: Int, context: String)
    case invalidString(offset: Int)
    case invalidStringValue(recordType: GDSRecordType, value: String)
    case recordPayloadTooLarge(recordType: GDSRecordType, payloadLength: Int)
    case invalidPayloadLength(offset: Int, dataType: GDSDataType, length: Int, alignment: Int)
}
