public struct IRProperty: Hashable, Sendable, Codable {
    public var attribute: Int16
    public var value: String

    public init(attribute: Int16, value: String) {
        self.attribute = attribute
        self.value = value
    }
}
