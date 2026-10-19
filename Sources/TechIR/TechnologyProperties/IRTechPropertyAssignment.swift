/// A typed property assignment retaining numeric lexical precision.
public struct IRTechPropertyAssignment: Hashable, Sendable, Codable {
    public enum Value: Hashable, Sendable, Codable {
        case integer(String)
        case real(String)
        case string(String)

        public var text: String {
            switch self {
            case .integer(let text), .real(let text), .string(let text): return text
            }
        }
        public var type: IRTechPropertyDefinition.ValueType {
            switch self {
            case .integer: return .integer
            case .real: return .real
            case .string: return .string
            }
        }
    }
    public var name: String
    public var value: Value

    public init(name: String, value: Value) { self.name = name; self.value = value }
}
