import Foundation

public enum DXFError: Error, Sendable, Equatable, LocalizedError {
    case invalidEncoding
    case incompleteGroup(line: Int)
    case invalidGroupCode(line: Int, value: String)
    case invalidNumber(entity: String, groupCode: Int, value: String)
    case numberOutOfRange(entity: String, groupCode: Int, value: String)
    case coordinateOutOfRange(entity: String, value: String)
    case missingRequiredGroup(entity: String, groupCode: Int)
    case invalidStructure(String)
    case unsupportedEntity(String)
    case unsupportedTransform(entity: String, reason: String)
    case invalidGeometry(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            "DXF input is not valid UTF-8."
        case .incompleteGroup(let line):
            "DXF group beginning at line \(line) has no value line."
        case .invalidGroupCode(let line, let value):
            "DXF group code at line \(line) is invalid: \(value)."
        case .invalidNumber(let entity, let code, let value):
            "DXF \(entity) group \(code) contains an invalid number: \(value)."
        case .numberOutOfRange(let entity, let code, let value):
            "DXF \(entity) group \(code) cannot be represented in layout coordinates: \(value)."
        case .coordinateOutOfRange(let entity, let value):
            "DXF \(entity) derived coordinate cannot be represented in layout coordinates: \(value)."
        case .missingRequiredGroup(let entity, let code):
            "DXF \(entity) is missing required group \(code)."
        case .invalidStructure(let reason):
            "DXF structure is invalid: \(reason)."
        case .unsupportedEntity(let entity):
            "DXF entity is not supported without loss: \(entity)."
        case .unsupportedTransform(let entity, let reason):
            "DXF \(entity) transform is not supported without loss: \(reason)."
        case .invalidGeometry(let reason):
            "DXF geometry cannot be written without loss: \(reason)."
        }
    }
}
