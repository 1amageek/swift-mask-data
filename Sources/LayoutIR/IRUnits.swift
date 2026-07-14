import CircuiteFoundation

public struct IRUnits: Hashable, Sendable, Codable {
    /// Database units per micrometer.
    public var dbuPerMicron: Double

    public init(dbuPerMicron: Double) {
        self.dbuPerMicron = dbuPerMicron
    }

    /// Creates IR units from the shared validated database-unit boundary.
    public init(scale: DatabaseUnitScale) {
        self.init(dbuPerMicron: scale.databaseUnitsPerMicrometer)
    }

    /// Returns the shared validated database-unit boundary for this IR value.
    ///
    /// The legacy non-throwing initializer remains available for format
    /// compatibility. New readers and writers should validate at their I/O
    /// boundary by calling this property before converting coordinates.
    public var validatedScale: DatabaseUnitScale {
        get throws {
            try DatabaseUnitScale(databaseUnitsPerMicrometer: dbuPerMicron)
        }
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
