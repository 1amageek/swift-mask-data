import Foundation

/// Errors that can occur while parsing a CIF document.
public enum CIFError: Error, Sendable, Equatable, LocalizedError {
    case invalidEncoding
    case unterminatedComment
    case unterminatedCommand(String)
    case unsupportedCommand(String)
    case invalidCommand(command: String, reason: String)
    case invalidNumber(String)
    case nestedCellDefinition
    case elementOutsideCell(String)
    case unterminatedCell(String)
    case unmatchedCellEnd
    case commandAfterEnd(String)
    case invalidOption(String)
    case unsupportedGeometry(String)
    case unsupportedTransform(String)
    case unresolvedCellReference(String)
    case duplicateCellName(String)
    case missingEndCommand

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            "CIF input is not valid UTF-8."
        case .unterminatedComment:
            "CIF input contains an unterminated parenthesized comment."
        case .unterminatedCommand(let command):
            "CIF command is not terminated by a semicolon: \(command)"
        case .unsupportedCommand(let command):
            "CIF command is unsupported: \(command)"
        case .invalidCommand(let command, let reason):
            "CIF command is malformed (\(reason)): \(command)"
        case .invalidNumber(let value):
            "CIF numeric token is invalid or out of range: \(value)"
        case .nestedCellDefinition:
            "CIF cell definitions cannot be nested."
        case .elementOutsideCell(let command):
            "CIF geometry command appears outside a cell definition: \(command)"
        case .unterminatedCell(let name):
            "CIF cell definition is missing DF: \(name)"
        case .unmatchedCellEnd:
            "CIF input contains DF without a matching DS."
        case .commandAfterEnd(let command):
            "CIF input contains a command after E: \(command)"
        case .invalidOption(let reason):
            "CIF writer option is invalid: \(reason)"
        case .unsupportedGeometry(let geometry):
            "CIF geometry cannot be represented without loss: \(geometry)"
        case .unsupportedTransform(let reason):
            "CIF transform cannot be represented without loss: \(reason)"
        case .unresolvedCellReference(let name):
            "CIF cell reference does not resolve to a library cell: \(name)"
        case .duplicateCellName(let name):
            "CIF library contains a duplicate cell name: \(name)"
        case .missingEndCommand:
            "CIF input is missing the terminal E command."
        }
    }
}
