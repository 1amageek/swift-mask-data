import TechIR

/// Retains declarations without interpreting assigned property-based process rules.
enum LEFPropertyDefinitionCodec {
    static func read(_ tokens: [String], from start: Int) throws -> (definitions: [IRTechPropertyDefinition], next: Int) {
        var index = start, definitions: [IRTechPropertyDefinition] = []
        while index < tokens.count, tokens[index].uppercased() != "END" {
            guard let end = tokens[index...].firstIndex(of: ";"), end - index >= 3,
                  let object = IRTechPropertyDefinition.ObjectType(rawValue: tokens[index].uppercased()),
                  let type = IRTechPropertyDefinition.ValueType(rawValue: tokens[index + 2].uppercased()) else {
                throw LEFError.invalidStructure("Invalid PROPERTYDEFINITIONS declaration")
            }
            let name = tokens[index + 1]
            index += 3
            var range: IRTechPropertyDefinition.NumericRange?
            if index < end, tokens[index].uppercased() == "RANGE" {
                guard index + 2 < end else { throw LEFError.invalidStructure("Incomplete property RANGE") }
                range = .init(lower: tokens[index + 1], upper: tokens[index + 2]); index += 3
            }
            guard end - index <= 1 else { throw LEFError.invalidStructure("Extra property definition values") }
            var value: String?
            if index < end {
                let token = tokens[index]
                value = token
                if type == .string {
                    guard token.hasPrefix("\""), token.hasSuffix("\""), token.count >= 2 else {
                        throw LEFError.invalidStructure("STRING property definition requires a quoted value")
                    }
                    value = String(token.dropFirst().dropLast())
                }
            }
            definitions.append(.init(objectType: object, name: name, valueType: type, range: range, libraryValue: value))
            index = end + 1
        }
        guard index + 1 < tokens.count, tokens[index].uppercased() == "END",
              tokens[index + 1].uppercased() == "PROPERTYDEFINITIONS" else {
            throw LEFError.invalidStructure("Unterminated PROPERTYDEFINITIONS")
        }
        try validate(definitions)
        return (definitions, index + 2)
    }

    static func validate(_ definitions: [IRTechPropertyDefinition]) throws {
        var names: Set<String> = []
        for definition in definitions {
            guard !definition.name.isEmpty, !definition.name.contains(where: { $0.isWhitespace || ";\"".contains($0) }),
                  names.insert(definition.objectType.rawValue + ":" + definition.name).inserted else {
                throw LEFError.invalidStructure("Invalid or repeated property definition name")
            }
            if let range = definition.range {
                guard definition.valueType != .string else { throw LEFError.invalidStructure("STRING cannot have RANGE") }
                if definition.valueType == .integer {
                    guard let lower = Int64(range.lower), let upper = Int64(range.upper), lower <= upper else {
                        throw LEFError.invalidStructure("Invalid INTEGER property RANGE")
                    }
                    if let value = definition.libraryValue {
                        guard let integer = Int64(value), integer >= lower, integer <= upper else {
                            throw LEFError.invalidStructure("INTEGER library property is outside RANGE")
                        }
                    }
                } else {
                    guard let lower = Double(range.lower), let upper = Double(range.upper), lower.isFinite, upper.isFinite, lower <= upper else {
                        throw LEFError.invalidStructure("Invalid REAL property RANGE")
                    }
                    if let value = definition.libraryValue {
                        guard let real = Double(value), real.isFinite, real >= lower, real <= upper else {
                            throw LEFError.invalidStructure("REAL library property is outside RANGE")
                        }
                    }
                }
            }
            if let value = definition.libraryValue {
                guard definition.objectType == .library else { throw LEFError.invalidStructure("Definition values belong to LIBRARY only") }
                switch definition.valueType {
                case .integer:
                    guard Int64(value) != nil else { throw LEFError.invalidStructure("Invalid INTEGER property value") }
                case .real:
                    guard let real = Double(value), real.isFinite else { throw LEFError.invalidStructure("Invalid REAL property value") }
                case .string:
                    guard !value.contains("\"") else { throw LEFError.invalidStructure("Unsupported quote in STRING property value") }
                }
            }
        }
    }

    static func write(_ definitions: [IRTechPropertyDefinition]) throws -> [String] {
        try validate(definitions)
        guard !definitions.isEmpty else { return [] }
        var lines = ["PROPERTYDEFINITIONS"]
        for definition in definitions {
            var line = "  \(definition.objectType.rawValue) \(definition.name) \(definition.valueType.rawValue)"
            if let range = definition.range { line += " RANGE \(range.lower) \(range.upper)" }
            if let value = definition.libraryValue { line += definition.valueType == .string ? " \"\(value)\"" : " \(value)" }
            lines.append(line + " ;")
        }
        lines.append("END PROPERTYDEFINITIONS")
        return lines
    }
}
