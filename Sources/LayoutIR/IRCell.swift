public struct IRCell: Hashable, Sendable, Codable {
    public var name: String
    public var elements: [IRElement]
    public var properties: [IRProperty]
    public var createdAt: IRDateTime?
    public var modifiedAt: IRDateTime?

    public init(
        name: String,
        elements: [IRElement] = [],
        properties: [IRProperty] = [],
        createdAt: IRDateTime? = nil,
        modifiedAt: IRDateTime? = nil
    ) {
        self.name = name
        self.elements = elements
        self.properties = properties
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case elements
        case properties
        case createdAt
        case modifiedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        elements = try container.decodeIfPresent([IRElement].self, forKey: .elements) ?? []
        properties = try container.decodeIfPresent([IRProperty].self, forKey: .properties) ?? []
        createdAt = try container.decodeIfPresent(IRDateTime.self, forKey: .createdAt)
        modifiedAt = try container.decodeIfPresent(IRDateTime.self, forKey: .modifiedAt)
    }
}
