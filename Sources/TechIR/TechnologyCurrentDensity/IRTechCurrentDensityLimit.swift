/// A scalar current-density limit with independent waveform class and physical units.
public struct IRTechCurrentDensityLimit: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        case dcAverage, acAverage, acPeak, acRMS
    }

    public enum Quantity: Hashable, Sendable, Codable {
        case milliamperesPerMicron(Double)
        case milliamperesPerSquareMicron(Double)

        public var value: Double {
            switch self {
            case .milliamperesPerMicron(let value), .milliamperesPerSquareMicron(let value): return value
            }
        }
    }

    public var kind: Kind
    public var quantity: Quantity

    public init(kind: Kind, quantity: Quantity) {
        self.kind = kind
        self.quantity = quantity
    }
}
