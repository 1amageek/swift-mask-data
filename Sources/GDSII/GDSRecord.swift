public struct GDSRecord: Sendable {
    public var recordType: GDSRecordType
    public var payload: GDSRecordPayload

    public init(recordType: GDSRecordType, payload: GDSRecordPayload) {
        self.recordType = recordType
        self.payload = payload
    }
}

public enum GDSRecordPayload: Sendable, Equatable {
    case noData
    case bitArray(UInt16)
    case int16([Int16])
    case int32([Int32])
    case real8([Double])
    case string(String)
}
