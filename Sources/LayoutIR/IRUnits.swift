public struct IRUnits: Hashable, Sendable, Codable {
    /// Database units per micrometer.
    public var dbuPerMicron: Double

    public init(dbuPerMicron: Double) {
        self.dbuPerMicron = dbuPerMicron
    }

    /// Meters per database unit, derived from dbuPerMicron.
    public var metersPerDBU: Double {
        1e-6 / dbuPerMicron
    }

    /// User units per database unit (microns per DBU).
    public var userUnitsPerDBU: Double {
        1.0 / dbuPerMicron
    }

    /// Default: 1000 DBU per µm (1 DBU = 1 nm).
    public static let `default` = IRUnits(dbuPerMicron: 1000)
}
