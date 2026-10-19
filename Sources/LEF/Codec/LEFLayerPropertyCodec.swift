import TechIR

/// Retains assigned values and validates the recognized layer classification rule.
enum LEFLayerPropertyCodec {
    private static let subtypes: [String: IRTechLayerSubtype] = [
        "NWELL": .nwell, "PWELL": .pwell, "ABOVEDIEEDGE": .aboveDieEdge,
        "BELOWDIEEDGE": .belowDieEdge, "DIFFUSION": .diffusion, "TRIMPOLY": .trimPoly,
        "TRIMMETAL": .trimMetal, "REGION": .region, "POLYROUTING": .polyRouting
    ]

    static func read(_ tokens: [String], from start: Int, definitions: [IRTechPropertyDefinition]) throws
        -> (properties: [IRTechPropertyAssignment], next: Int) {
        guard start + 2 < tokens.count, tokens[start + 2] == ";",
              let definition = definitions.first(where: { $0.objectType == .layer && $0.name == tokens[start] }) else {
            throw LEFError.invalidStructure("LAYER PROPERTY requires one declared name/value pair")
        }
        let token = tokens[start + 1]
        let value: IRTechPropertyAssignment.Value
        switch definition.valueType {
        case .integer: value = .integer(token)
        case .real: value = .real(token)
        case .string:
            guard token.hasPrefix("\""), token.hasSuffix("\""), token.count >= 2 else {
                throw LEFError.invalidStructure("STRING layer property requires a quoted value")
            }
            value = .string(String(token.dropFirst().dropLast()))
        }
        let property = IRTechPropertyAssignment(name: definition.name, value: value)
        try validate([property], definitions: definitions)
        return ([property], start + 3)
    }

    static func validate(_ properties: [IRTechPropertyAssignment], definitions: [IRTechPropertyDefinition]) throws {
        var names: Set<String> = []
        for property in properties {
            guard names.insert(property.name).inserted,
                  let definition = definitions.first(where: { $0.objectType == .layer && $0.name == property.name }),
                  definition.valueType == property.value.type else {
                throw LEFError.invalidStructure("Undeclared, repeated or mistyped LAYER PROPERTY \(property.name)")
            }
            // Reuse definition numeric/range validation without converting or rounding the value.
            var validation = definition
            validation.objectType = .library
            validation.libraryValue = property.value.text
            try LEFPropertyDefinitionCodec.validate([validation])
        }
    }

    static func subtype(_ properties: [IRTechPropertyAssignment], type: LEFLayerDef.LayerType) throws -> IRTechLayerSubtype? {
        guard let property = properties.first(where: { $0.name == "LEF58_TYPE" }) else { return nil }
        guard case .string(let text) = property.value else {
            throw LEFError.invalidStructure("LEF58_TYPE requires STRING")
        }
        let tokens = try LEFTokenizer.tokenize(text)
        guard tokens.count == 3, tokens[0].uppercased() == "TYPE", tokens[2] == ";",
              let subtype = subtypes[tokens[1].uppercased()] else {
            throw LEFError.unsupportedCommand("LEF58_TYPE \(text)")
        }
        guard subtype == .polyRouting ? type == .routing : type == .masterslice else {
            throw LEFError.invalidStructure("LEF58_TYPE is incompatible with \(type.rawValue)")
        }
        return subtype
    }

    static func validate(_ layer: LEFLayerDef, definitions: [IRTechPropertyDefinition]) throws {
        try validate(layer.properties, definitions: definitions)
        guard layer.subtype == (try subtype(layer.properties, type: layer.type)) else {
            throw LEFError.invalidStructure("Layer subtype disagrees with LEF58_TYPE assignment")
        }
    }

    static func write(_ property: IRTechPropertyAssignment) -> String {
        let text = property.value.type == .string ? "\"\(property.value.text)\"" : property.value.text
        return "  PROPERTY \(property.name) \(text) ;"
    }
}
