/// An ordered antenna declaration; oxide scope follows preceding model statements.
public enum IRTechAntennaStatement: Hashable, Sendable, Codable {
    public enum Oxide: String, Hashable, Sendable, Codable {
        case oxide1, oxide2, oxide3, oxide4
    }

    public enum RatioKind: String, Hashable, Sendable, Codable {
        /// Routing metal area or cut area divided by gate area, for diffusion-connected conductors.
        case diffusionArea
        /// Routing metal sidewall area divided by gate area, for diffusion-connected conductors.
        case diffusionSideArea
    }

    public struct Point: Hashable, Sendable, Codable {
        public var diffusionAreaSquareMicrons: Double
        public var ratio: Double

        public init(diffusionAreaSquareMicrons: Double, ratio: Double) {
            self.diffusionAreaSquareMicrons = diffusionAreaSquareMicrons
            self.ratio = ratio
        }
    }

    public enum RatioValue: Hashable, Sendable, Codable {
        case scalar(Double)
        /// Linear interpolation between ordered diffusion-area coordinates.
        case piecewiseLinear([Point])
    }

    case model(Oxide)
    case ratio(kind: RatioKind, value: RatioValue)
}
