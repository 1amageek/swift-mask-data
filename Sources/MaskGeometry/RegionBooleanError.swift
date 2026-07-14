/// Failure raised by an exact-only region boolean operation.
public enum RegionBooleanError: Error, Equatable, Sendable {
    case unsupportedNonManhattanGeometry(operand: String, polygonIndex: Int)
    case invalidManhattanGeometry(operand: String, polygonIndex: Int)
}
