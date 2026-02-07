/// Tracks modal variables within an OASIS cell.
///
/// OASIS uses modal variables to avoid repeating unchanged values
/// between consecutive geometry records within the same cell.
public struct OASISModalState: Sendable {
    public var layer: UInt64?
    public var datatype: UInt64?
    public var textlayer: UInt64?
    public var texttype: UInt64?
    public var x: Int64?
    public var y: Int64?
    public var geometryW: UInt64?
    public var geometryH: UInt64?
    public var pathHalfwidth: UInt64?
    public var cellName: String?
    public var textString: String?
    public var ctrapType: UInt64?
    public var circleRadius: UInt64?
    public var lastRepetition: OASISRepetition?
    public var lastPropertyName: String?
    public var lastPropertyValues: [OASISPropertyValue]?

    public init() {}

    public mutating func reset() {
        layer = nil
        datatype = nil
        textlayer = nil
        texttype = nil
        x = nil
        y = nil
        geometryW = nil
        geometryH = nil
        pathHalfwidth = nil
        cellName = nil
        textString = nil
        ctrapType = nil
        circleRadius = nil
        lastRepetition = nil
        lastPropertyName = nil
        lastPropertyValues = nil
    }
}
