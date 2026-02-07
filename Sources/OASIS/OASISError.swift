public enum OASISError: Error, Sendable {
    case invalidMagic(offset: Int)
    case unexpectedEndOfData(offset: Int)
    case unknownRecordType(offset: Int, rawValue: UInt8)
    case unknownRealType(offset: Int, typeCode: UInt64)
    case invalidString(offset: Int)
    case unexpectedRecord(got: UInt8, expected: String, offset: Int)
    case invalidPointListType(offset: Int, typeCode: UInt64)
    case invalidRepetitionType(offset: Int, typeCode: UInt64)
    case decompressFailure(offset: Int)
    case invalidCTrapezoidType(offset: Int, typeCode: UInt64)
}
