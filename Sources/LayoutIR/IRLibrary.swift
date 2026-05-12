public struct IRLibrary: Hashable, Sendable, Codable {
    public var name: String
    public var units: IRUnits
    public var cells: [IRCell]
    /// File-level metadata (e.g. OASIS standard properties).
    public var metadata: [String: String]
    public var createdAt: IRDateTime?
    public var modifiedAt: IRDateTime?

    public init(
        name: String,
        units: IRUnits = .default,
        cells: [IRCell] = [],
        metadata: [String: String] = [:],
        createdAt: IRDateTime? = nil,
        modifiedAt: IRDateTime? = nil
    ) {
        self.name = name
        self.units = units
        self.cells = cells
        self.metadata = metadata
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public func cell(named name: String) -> IRCell? {
        cells.first { $0.name == name }
    }
}
