/// Type classification for technology layers.
public enum IRTechLayerType: String, Hashable, Sendable, Codable {
    case routing
    case cut
    case masterslice
    case overlap
    case implant
}
