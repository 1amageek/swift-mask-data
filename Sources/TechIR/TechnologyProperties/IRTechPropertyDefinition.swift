/// A retained scalar property declaration, independent of process-rule interpretation.
public struct IRTechPropertyDefinition: Hashable, Sendable, Codable {
    public enum ObjectType: String, Hashable, Sendable, Codable {
        case library = "LIBRARY", layer = "LAYER", macro = "MACRO", nondefaultRule = "NONDEFAULTRULE"
        case pin = "PIN", via = "VIA", viaRule = "VIARULE"
    }
    public enum ValueType: String, Hashable, Sendable, Codable {
        case integer = "INTEGER", real = "REAL", string = "STRING"
    }
    public struct NumericRange: Hashable, Sendable, Codable {
        public var lower: String
        public var upper: String
        public init(lower: String, upper: String) { self.lower = lower; self.upper = upper }
    }
    public var objectType: ObjectType
    public var name: String
    public var valueType: ValueType
    public var range: NumericRange?
    public var libraryValue: String?

    public init(objectType: ObjectType, name: String, valueType: ValueType,
                range: NumericRange? = nil, libraryValue: String? = nil) {
        self.objectType = objectType; self.name = name; self.valueType = valueType
        self.range = range; self.libraryValue = libraryValue
    }
}
