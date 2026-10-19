/// A recognized technology layer classification, independent of source syntax.
public enum IRTechLayerSubtype: String, Hashable, Sendable, Codable {
    case nwell, pwell, aboveDieEdge, belowDieEdge, diffusion, trimPoly, trimMetal, region, polyRouting
}
