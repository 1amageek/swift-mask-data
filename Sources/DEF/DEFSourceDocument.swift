/// Original-source facts admitted by the explicit routed PEX reader profile.
public struct DEFSourceDocument: Sendable {
    public let document: DEFDocument
    public let unitsDeclaration: UnitsDeclaration

    public struct UnitsDeclaration: Hashable, Sendable {
        public let dbuPerMicron: Double
        public let literal: String
        /// Zero-based tokens from UNITS through its terminating semicolon, not bytes.
        public let tokenRange: Range<Int>
    }
}
