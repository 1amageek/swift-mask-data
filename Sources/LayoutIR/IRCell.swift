public struct IRCell: Hashable, Sendable, Codable {
    public var name: String
    public var elements: [IRElement]
    public var createdAt: IRDateTime?
    public var modifiedAt: IRDateTime?

    public init(
        name: String,
        elements: [IRElement] = [],
        createdAt: IRDateTime? = nil,
        modifiedAt: IRDateTime? = nil
    ) {
        self.name = name
        self.elements = elements
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}
