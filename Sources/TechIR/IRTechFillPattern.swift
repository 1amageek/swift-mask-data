/// Fill pattern for layer visualization.
public enum IRTechFillPattern: String, Hashable, Sendable, Codable {
    case solid
    case forwardDiagonal
    case backwardDiagonal
    case crosshatch
    case horizontal
    case vertical
    case grid
    case dots
}
