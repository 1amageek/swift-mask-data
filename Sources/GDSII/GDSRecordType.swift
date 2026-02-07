public enum GDSRecordType: UInt8, Sendable {
    case header       = 0x00
    case bgnlib       = 0x01
    case libname      = 0x02
    case units        = 0x03
    case endlib       = 0x04
    case bgnstr       = 0x05
    case strname      = 0x06
    case endstr       = 0x07
    case boundary     = 0x08
    case path         = 0x09
    case sref         = 0x0A
    case aref         = 0x0B
    case text         = 0x0C
    case layer        = 0x0D
    case datatype     = 0x0E
    case width        = 0x0F
    case xy           = 0x10
    case endel        = 0x11
    case sname        = 0x12
    case colrow       = 0x13
    case node         = 0x15
    case texttype     = 0x16
    case presentation = 0x17
    case string       = 0x19
    case strans       = 0x1A
    case mag          = 0x1B
    case angle        = 0x1C
    case reflibs      = 0x1F
    case fonts        = 0x20
    case pathtype     = 0x21
    case generations  = 0x22
    case attrtable    = 0x23
    case elflags      = 0x26
    case nodetype     = 0x2A
    case propattr     = 0x2B
    case propvalue    = 0x2C
    case box          = 0x2D
    case boxtype      = 0x2E
    case plex         = 0x2F
    case bgnextn      = 0x30
    case endextn      = 0x31
    case format       = 0x36

    /// Explicit initializer to work around Swift compiler optimization issues
    /// with sparse UInt8 enum rawValue tables.
    public init?(validating rawValue: UInt8) {
        // Use a switch to guarantee correct mapping
        switch rawValue {
        case 0x00: self = .header
        case 0x01: self = .bgnlib
        case 0x02: self = .libname
        case 0x03: self = .units
        case 0x04: self = .endlib
        case 0x05: self = .bgnstr
        case 0x06: self = .strname
        case 0x07: self = .endstr
        case 0x08: self = .boundary
        case 0x09: self = .path
        case 0x0A: self = .sref
        case 0x0B: self = .aref
        case 0x0C: self = .text
        case 0x0D: self = .layer
        case 0x0E: self = .datatype
        case 0x0F: self = .width
        case 0x10: self = .xy
        case 0x11: self = .endel
        case 0x12: self = .sname
        case 0x13: self = .colrow
        case 0x15: self = .node
        case 0x16: self = .texttype
        case 0x17: self = .presentation
        case 0x19: self = .string
        case 0x1A: self = .strans
        case 0x1B: self = .mag
        case 0x1C: self = .angle
        case 0x1F: self = .reflibs
        case 0x20: self = .fonts
        case 0x21: self = .pathtype
        case 0x22: self = .generations
        case 0x23: self = .attrtable
        case 0x26: self = .elflags
        case 0x2A: self = .nodetype
        case 0x2B: self = .propattr
        case 0x2C: self = .propvalue
        case 0x2D: self = .box
        case 0x2E: self = .boxtype
        case 0x2F: self = .plex
        case 0x30: self = .bgnextn
        case 0x31: self = .endextn
        case 0x36: self = .format
        default: return nil
        }
    }
}
