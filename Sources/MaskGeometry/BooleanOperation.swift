/// Boolean operations supported by the exact region kernel.
enum BooleanOperation: Sendable {
    case intersection
    case union
    case symmetricDifference
    case subtraction
}
