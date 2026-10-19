import TechIR

/// Validates and retains source laws without performing process antenna evaluation.
enum LEFAntennaCodec {
    static let commands: Set<String> = ["ANTENNAMODEL", "ANTENNADIFFAREARATIO", "ANTENNADIFFSIDEAREARATIO"]

    static func read(_ tokens: [String], from start: Int) throws -> (statement: IRTechAntennaStatement, next: Int) {
        let command = tokens[start].uppercased()
        guard let end = tokens[(start + 1)...].firstIndex(of: ";") else {
            throw LEFError.missingSemicolon(command: command)
        }
        let values = splitPunctuation(tokens[(start + 1)..<end])
        let statement: IRTechAntennaStatement
        if command == "ANTENNAMODEL" {
            guard values.count == 1, let token = values.first,
                  let oxide = IRTechAntennaStatement.Oxide(rawValue: token.lowercased()) else {
                throw LEFError.invalidStructure("ANTENNAMODEL requires OXIDE1 through OXIDE4")
            }
            statement = .model(oxide)
        } else {
            let kind: IRTechAntennaStatement.RatioKind
            switch command {
            case "ANTENNADIFFAREARATIO": kind = .diffusionArea
            case "ANTENNADIFFSIDEAREARATIO": kind = .diffusionSideArea
            default: throw LEFError.unsupportedCommand(command)
            }
            if values.count == 1, let token = values.first {
                statement = .ratio(kind: kind, value: .scalar(try number(token, command: command)))
            } else {
                var index = 0
                guard index + 1 < values.count, values[index].uppercased() == "PWL", values[index + 1] == "(" else {
                    throw LEFError.invalidStructure("\(command) requires a scalar or PWL table")
                }
                index += 2
                var points: [IRTechAntennaStatement.Point] = []
                while index < values.count, values[index] != ")" {
                    guard index + 3 < values.count, values[index] == "(", values[index + 3] == ")" else {
                        throw LEFError.invalidStructure("\(command) PWL requires complete diffusion/ratio pairs")
                    }
                    points.append(.init(diffusionAreaSquareMicrons: try number(values[index + 1], command: command),
                                        ratio: try number(values[index + 2], command: command)))
                    index += 4
                }
                guard index == values.count - 1, values[index] == ")" else {
                    throw LEFError.invalidStructure("\(command) PWL has unmatched parentheses or extra values")
                }
                statement = .ratio(kind: kind, value: .piecewiseLinear(points))
            }
        }
        try validate(statement)
        return (statement, end + 1)
    }

    // Parentheses delimit antenna pairs without changing identifier tokenization elsewhere.
    private static func splitPunctuation(_ values: ArraySlice<String>) -> [String] {
        var result: [String] = []
        for value in values {
            var word = ""
            for character in value {
                if character == "(" || character == ")" {
                    if !word.isEmpty { result.append(word); word = "" }
                    result.append(String(character))
                } else { word.append(character) }
            }
            if !word.isEmpty { result.append(word) }
        }
        return result
    }

    static func validate(_ statements: [IRTechAntennaStatement], layerType: LEFLayerDef.LayerType) throws {
        for statement in statements {
            guard layerType == .routing || layerType == .cut else {
                throw LEFError.invalidStructure("Layer antenna declarations require ROUTING or CUT")
            }
            if case .ratio(kind: .diffusionSideArea, value: _) = statement, layerType != .routing {
                throw LEFError.invalidStructure("ANTENNADIFFSIDEAREARATIO requires ROUTING")
            }
            try validate(statement)
        }
    }

    private static func validate(_ statement: IRTechAntennaStatement) throws {
        guard case .ratio(_, let value) = statement else { return }
        switch value {
        case .scalar(let ratio): try validateNumber(ratio)
        case .piecewiseLinear(let points):
            guard points.count >= 2 else { throw LEFError.invalidStructure("Antenna PWL requires at least two points") }
            var previous: Double?
            for point in points {
                try validateNumber(point.diffusionAreaSquareMicrons)
                try validateNumber(point.ratio)
                if let previous, point.diffusionAreaSquareMicrons <= previous {
                    throw LEFError.invalidStructure("Antenna PWL diffusion areas must strictly increase")
                }
                previous = point.diffusionAreaSquareMicrons
            }
        }
    }

    private static func number(_ token: String, command: String) throws -> Double {
        guard let value = Double(token) else { throw LEFError.invalidNumber(command: command, value: token) }
        try validateNumber(value)
        return value
    }

    private static func validateNumber(_ value: Double) throws {
        // Cadence LEF 5.8 int_number admits fractions within signed 64-bit magnitude.
        guard value.isFinite, value >= 0, value <= Double(Int64.max) else {
            throw LEFError.invalidNumber(command: "ANTENNA", value: String(value))
        }
    }

    static func write(_ statement: IRTechAntennaStatement) -> String {
        switch statement {
        case .model(let oxide): return "  ANTENNAMODEL \(oxide.rawValue.uppercased()) ;"
        case .ratio(let kind, let value):
            let command = kind == .diffusionArea ? "ANTENNADIFFAREARATIO" : "ANTENNADIFFSIDEAREARATIO"
            let text: String
            switch value {
            case .scalar(let ratio): text = String(ratio)
            case .piecewiseLinear(let points):
                text = "PWL ( " + points.map { "( \($0.diffusionAreaSquareMicrons) \($0.ratio) )" }.joined(separator: " ") + " )"
            }
            return "  \(command) \(text) ;"
        }
    }
}
