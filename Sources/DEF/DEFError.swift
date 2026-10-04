public enum DEFError: Error, Sendable, Equatable {
    case unsupportedRouteFeature(context: String, feature: String)
    case invalidEncoding
    case missingNumber(context: String)
    case invalidNumber(context: String, token: String)
}
