public struct IRTransform: Hashable, Sendable, Codable {
    /// Reflect about X axis before rotation.
    public var mirrorX: Bool
    /// Magnification factor.
    public var magnification: Double
    /// Rotation angle in degrees (counterclockwise).
    public var angle: Double

    public init(mirrorX: Bool = false, magnification: Double = 1.0, angle: Double = 0.0) {
        self.mirrorX = mirrorX
        self.magnification = magnification
        self.angle = angle
    }

    public static let identity = IRTransform()
}
