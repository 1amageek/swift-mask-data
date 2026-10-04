/// A resolved endpoint value retains explicit source intent across width changes.
enum OASISPathEndpoint: Sendable {
    case flush
    case halfWidth(Int64)
    case explicit(Int64)

    var value: Int64 {
        switch self {
        case .flush: 0
        case .halfWidth(let value), .explicit(let value): value
        }
    }

    var isExplicit: Bool {
        if case .explicit = self { return true }
        return false
    }
}
