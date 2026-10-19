import TechIR

/// Retains the bounded GENERATE profile without materializing a via instance.
enum LEFViaGenerationCodec {
    static func read(_ tokens: [String], from start: Int) throws -> (rule: IRTechViaGenerationRule, next: Int) {
        var index = start + 1

        func atom() throws -> String {
            guard index < tokens.count else { throw LEFError.missingValue(command: "VIARULE") }
            let value = tokens[index]
            try validateAtom(value)
            index += 1
            return value
        }
        func expect(_ command: String) throws {
            guard index < tokens.count else { throw LEFError.missingValue(command: command) }
            try refuseVariant(tokens[index])
            guard tokens[index].uppercased() == command else {
                throw LEFError.invalidStructure("Expected \(command) in VIARULE GENERATE, received \(tokens[index])")
            }
            index += 1
        }
        func numbers(_ command: String, count: Int, separator: String? = nil) throws -> [Double] {
            try expect(command)
            guard let end = tokens[index...].firstIndex(of: ";") else {
                throw LEFError.missingSemicolon(command: command)
            }
            var values = Array(tokens[index..<end])
            if values.contains(where: { $0.uppercased() == "END" }) {
                throw LEFError.missingSemicolon(command: command)
            }
            if let separator {
                guard values.count == count + 1, values[1].uppercased() == separator else {
                    throw LEFError.invalidStructure("\(command) requires X \(separator) Y")
                }
                values.remove(at: 1)
            }
            guard values.count == count else {
                throw LEFError.invalidStructure("\(command) has unsupported arity in VIARULE GENERATE")
            }
            let parsed = try values.map { value in
                guard let number = Double(value), number.isFinite else {
                    throw LEFError.invalidNumber(command: command, value: value)
                }
                return number
            }
            index = end + 1
            return parsed
        }
        func layerName() throws -> String {
            try expect("LAYER")
            let name = try atom()
            try expect(";")
            return name
        }

        let name = try atom()
        guard index < tokens.count, tokens[index].uppercased() == "GENERATE" else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Non-GENERATE rules lack retained
            // fixed-via selection semantics. Production preflight refuses them until
            // exact source/writer/projection behavior exists without losing selection.
            throw LEFError.unsupportedCommand("VIARULE without GENERATE")
        }
        index += 1
        var routing: [IRTechViaGenerationRule.RoutingLayer] = []
        for _ in 0..<2 {
            let layer = try layerName()
            let enclosure = try numbers("ENCLOSURE", count: 2)
            routing.append(.init(layerName: layer, enclosure: .init(overhang1: enclosure[0], overhang2: enclosure[1])))
        }
        let cut = try layerName()
        let rect = try numbers("RECT", count: 4)
        let spacing = try numbers("SPACING", count: 2, separator: "BY")
        try expect("END")
        let endName = try atom()
        guard endName == name else { throw LEFError.mismatchedEnd(expected: name, actual: endName) }
        let rule = IRTechViaGenerationRule(name: name, routingLayers: routing, cutLayerName: cut,
            cutRectangle: .init(x1: rect[0], y1: rect[1], x2: rect[2], y2: rect[3]),
            cutCenterSpacing: .xy(x: spacing[0], y: spacing[1]))
        try validateValue(rule)
        return (rule, index)
    }

    private static func refuseVariant(_ token: String) throws {
        if ["DEFAULT", "WIDTH", "RESISTANCE", "PROPERTY", "DIRECTION", "OVERHANG", "METALOVERHANG"].contains(token.uppercased()) {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Optional and legacy VIARULE forms
            // lack retained selectors/electrical facts. Production preflight refuses
            // them until faithful source/writer/projection contracts are verified.
            throw LEFError.unsupportedCommand("\(token.uppercased()) in VIARULE GENERATE")
        }
    }

    private static func validateAtom(_ value: String) throws {
        guard !value.isEmpty, !value.contains(where: { $0.isWhitespace || $0 == ";" || $0 == "\"" || $0 == "#" }) else {
            throw LEFError.invalidStructure("VIARULE names require a single unquoted token")
        }
    }

    private static func validateValue(_ rule: IRTechViaGenerationRule) throws {
        try validateAtom(rule.name)
        guard rule.name.uppercased() != "DEFAULT", rule.routingLayers.count == 2 else {
            throw LEFError.invalidStructure("VIARULE GENERATE requires a nonreserved name and two routing layers")
        }
        let names = rule.routingLayers.map(\.layerName) + [rule.cutLayerName]
        guard Set(names).count == 3 else {
            throw LEFError.invalidStructure("VIARULE GENERATE requires three distinct layer names")
        }
        for name in names { try validateAtom(name) }
        for layer in rule.routingLayers {
            guard layer.enclosure.overhang1.isFinite, layer.enclosure.overhang2.isFinite else {
                throw LEFError.invalidNumber(command: "ENCLOSURE", value: "non-finite")
            }
        }
        let rect = rule.cutRectangle
        guard [rect.x1, rect.y1, rect.x2, rect.y2].allSatisfy(\.isFinite), rect.x1 < rect.x2, rect.y1 < rect.y2 else {
            throw LEFError.invalidGeometry("VIARULE cut RECT requires finite coordinates and positive extents")
        }
        guard case .xy(let x, let y) = rule.cutCenterSpacing, x.isFinite, y.isFinite, x > 0, y > 0 else {
            throw LEFError.invalidNumber(command: "VIARULE SPACING", value: "requires explicit finite positive X/Y center spacing")
        }
    }

    static func validate(_ rules: [IRTechViaGenerationRule], layers: [LEFLayerDef]) throws {
        var names: Set<String> = []
        for rule in rules {
            try validateValue(rule)
            guard names.insert(rule.name).inserted else {
                throw LEFError.invalidStructure("Repeated VIARULE name \(rule.name)")
            }
            for (name, type) in rule.routingLayers.map({ ($0.layerName, LEFLayerDef.LayerType.routing) }) + [(rule.cutLayerName, .cut)] {
                let matches = layers.filter { $0.name == name }
                guard matches.count == 1, matches[0].type == type else {
                    throw LEFError.invalidStructure("VIARULE layer \(name) requires one unambiguous \(type.rawValue) declaration")
                }
            }
        }
    }

    static func write(_ rule: IRTechViaGenerationRule) -> [String] {
        var lines = ["VIARULE \(rule.name) GENERATE"]
        for layer in rule.routingLayers {
            lines.append("  LAYER \(layer.layerName) ;")
            lines.append("  ENCLOSURE \(layer.enclosure.overhang1) \(layer.enclosure.overhang2) ;")
        }
        let rect = rule.cutRectangle
        lines.append("  LAYER \(rule.cutLayerName) ;")
        lines.append("  RECT \(rect.x1) \(rect.y1) \(rect.x2) \(rect.y2) ;")
        lines.append("  SPACING \(rule.cutCenterSpacing.x) BY \(rule.cutCenterSpacing.y) ;")
        lines.append("END \(rule.name)")
        return lines
    }
}
