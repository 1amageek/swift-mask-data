public enum GDSDataType: UInt8, Sendable {
    case noData   = 0x00
    case bitArray = 0x01
    case int16    = 0x02
    case int32    = 0x03
    case real4    = 0x04
    case real8    = 0x05
    case string   = 0x06
}
