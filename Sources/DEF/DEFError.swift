public enum DEFError: Error, Sendable, Equatable {
    case unsupportedRouteFeature(context: String, feature: String)
    case unsupportedPinFeature(pinName: String, feature: String)
    case invalidPinValue(pinName: String, field: String, token: String)
    case invalidPinSyntax(pinName: String, expected: String, token: String?)
    case invalidEncoding
    case missingNumber(context: String)
    case invalidNumber(context: String, token: String)
}
