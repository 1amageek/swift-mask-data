/// Represents an OASIS repetition structure.
public enum OASISRepetition: Sendable, Equatable {
    /// Regular 2D grid: columns × rows with uniform spacing.
    case grid(columns: UInt64, rows: UInt64, colSpacing: UInt64, rowSpacing: UInt64)
    /// Uniform row: count copies spaced equally along x.
    case uniformRow(count: UInt64, spacing: UInt64)
    /// Uniform column: count copies spaced equally along y.
    case uniformColumn(count: UInt64, spacing: UInt64)
    /// Variable row: copies with individual spacings along x.
    case variableRow(spacings: [UInt64])
    /// Variable column: copies with individual spacings along y.
    case variableColumn(spacings: [UInt64])
    /// Arbitrary 2D grid with displacement vectors.
    case arbitraryGrid(columns: UInt64, rows: UInt64, colDisplacement: OASISDisplacement, rowDisplacement: OASISDisplacement)
    /// Variable row with displacement vector per element.
    case variableDisplacementRow(displacements: [OASISDisplacement])
    /// Variable column with displacement vector per element.
    case variableDisplacementColumn(displacements: [OASISDisplacement])
}

/// A 2D displacement vector used in OASIS repetitions.
public struct OASISDisplacement: Sendable, Equatable, Hashable {
    public var dx: Int64
    public var dy: Int64
    public init(dx: Int64, dy: Int64) {
        self.dx = dx
        self.dy = dy
    }
}

/// A property value in OASIS records.
public enum OASISPropertyValue: Sendable, Equatable {
    case real(Double)
    case unsignedInteger(UInt64)
    case signedInteger(Int64)
    case aString(String)
    case bString([UInt8])
    case reference(UInt64)
}
