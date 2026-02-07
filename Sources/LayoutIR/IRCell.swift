public struct IRCell: Hashable, Sendable, Codable {
    public var name: String
    public var elements: [IRElement]

    public init(name: String, elements: [IRElement] = []) {
        self.name = name
        self.elements = elements
    }
}
