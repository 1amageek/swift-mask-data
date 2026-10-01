/// A scalar or explicit X/Y declaration, measured in micrometers.
public enum IRTechAxisValue: Hashable, Sendable, Codable {
    case scalar(Double)
    case xy(x: Double, y: Double)

    public var x: Double {
        switch self {
        case .scalar(let value): value
        case .xy(let x, _): x
        }
    }

    public var y: Double {
        switch self {
        case .scalar(let value): value
        case .xy(_, let y): y
        }
    }
}
