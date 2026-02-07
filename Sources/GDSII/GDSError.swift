public enum GDSError: Error, Sendable {
    case unexpectedEndOfData(offset: Int)
    case invalidRecordLength(offset: Int, length: UInt16)
    case unknownRecordType(offset: Int, rawValue: UInt8)
    case unknownDataType(offset: Int, rawValue: UInt8)
    case missingRequiredRecord(GDSRecordType, context: String)
    case unexpectedRecord(got: GDSRecordType, expected: GDSRecordType, offset: Int)
    case invalidString(offset: Int)
}
