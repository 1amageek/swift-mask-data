public enum DEFError: Error, Sendable, Equatable {
    case invalidEncoding
    case missingNumber(context: String)
    case invalidNumber(context: String, token: String)
}
