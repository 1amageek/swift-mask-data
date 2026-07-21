import Foundation

public enum LEFError: Error, Sendable, Equatable, LocalizedError {
    case invalidEncoding
    case unterminatedQuotedString
    case unsupportedCommand(String)
    case missingValue(command: String)
    case missingSemicolon(command: String)
    case invalidNumber(command: String, value: String)
    case invalidStructure(String)
    case mismatchedEnd(expected: String, actual: String?)
    case unresolvedLayer(String)
    case layerIdentifierOutOfRange(layerCount: Int)
    case coordinateOutOfRange(context: String, value: String)
    case invalidGeometry(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding: "LEF input is not valid UTF-8."
        case .unterminatedQuotedString: "LEF input contains an unterminated quoted string."
        case .unsupportedCommand(let command): "LEF command is not supported without loss: \(command)."
        case .missingValue(let command): "LEF command \(command) is missing a required value."
        case .missingSemicolon(let command): "LEF command \(command) is missing its terminating semicolon."
        case .invalidNumber(let command, let value): "LEF command \(command) contains an invalid number: \(value)."
        case .invalidStructure(let reason): "LEF structure is invalid: \(reason)."
        case .mismatchedEnd(let expected, let actual):
            "LEF END mismatch; expected \(expected), received \(actual ?? "no name")."
        case .unresolvedLayer(let name):
            "LEF geometry references an undefined layer: \(name)."
        case .layerIdentifierOutOfRange(let layerCount):
            "LEF contains \(layerCount) layers, which exceeds the LayoutIR layer identifier range."
        case .coordinateOutOfRange(let context, let value):
            "LEF \(context) cannot be represented in LayoutIR coordinates: \(value)."
        case .invalidGeometry(let reason):
            "LEF geometry cannot be converted without loss: \(reason)."
        }
    }
}
