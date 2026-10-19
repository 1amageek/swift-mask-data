import TechIR

/// Retains scalar electrical limits under the standard layer-dependent unit authority.
enum LEFCurrentDensityCodec {
    static let commands: Set<String> = ["DCCURRENTDENSITY", "ACCURRENTDENSITY"]

    static func read(_ tokens: [String], from start: Int) throws
        -> (kind: IRTechCurrentDensityLimit.Kind, value: Double, next: Int) {
        let command = tokens[start].uppercased()
        guard let end = tokens[(start + 1)...].firstIndex(of: ";") else {
            throw LEFError.missingSemicolon(command: command)
        }
        let values = tokens[(start + 1)..<end]
        if let table = values.first(where: { ["FREQUENCY", "WIDTH", "CUTAREA", "TABLEENTRIES"].contains($0.uppercased()) }) {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Current-density tables lack retained
            // axes and cells. Production LEF preflight refuses them until exact
            // source/writer/projection contracts and electrical evaluation are verified.
            throw LEFError.unsupportedCommand("\(command) \(table.uppercased()) table")
        }
        guard values.count == 2, let classification = values.first?.uppercased(),
              let token = values.last, let value = Double(token) else {
            throw LEFError.invalidStructure("\(command) requires one classification and scalar")
        }
        let kind: IRTechCurrentDensityLimit.Kind
        switch (command, classification) {
        case ("DCCURRENTDENSITY", "AVERAGE"): kind = .dcAverage
        case ("ACCURRENTDENSITY", "AVERAGE"): kind = .acAverage
        case ("ACCURRENTDENSITY", "PEAK"): kind = .acPeak
        case ("ACCURRENTDENSITY", "RMS"): kind = .acRMS
        default: throw LEFError.invalidStructure("Unsupported \(command) classification \(classification)")
        }
        try validateNumber(value)
        return (kind, value, end + 1)
    }

    static func makeLimit(kind: IRTechCurrentDensityLimit.Kind, value: Double,
                          layerType: LEFLayerDef.LayerType) throws -> IRTechCurrentDensityLimit {
        switch layerType {
        case .routing: return .init(kind: kind, quantity: .milliamperesPerMicron(value))
        case .cut: return .init(kind: kind, quantity: .milliamperesPerSquareMicron(value))
        default: throw LEFError.invalidStructure("Current density requires ROUTING or CUT")
        }
    }

    static func validate(_ layer: LEFLayerDef) throws {
        var kinds: Set<IRTechCurrentDensityLimit.Kind> = []
        for limit in layer.currentDensityLimits {
            guard kinds.insert(limit.kind).inserted else {
                throw LEFError.invalidStructure("Repeated current-density classification")
            }
            switch (layer.type, limit.quantity) {
            case (.routing, .milliamperesPerMicron), (.cut, .milliamperesPerSquareMicron): break
            default: throw LEFError.invalidStructure("Current-density units disagree with layer type")
            }
            try validateNumber(limit.quantity.value)
        }
    }

    private static func validateNumber(_ value: Double) throws {
        guard value.isFinite, value >= 0 else {
            throw LEFError.invalidNumber(command: "CURRENTDENSITY", value: String(value))
        }
    }

    static func write(_ limit: IRTechCurrentDensityLimit) -> String {
        let declaration: String
        switch limit.kind {
        case .dcAverage: declaration = "DCCURRENTDENSITY AVERAGE"
        case .acAverage: declaration = "ACCURRENTDENSITY AVERAGE"
        case .acPeak: declaration = "ACCURRENTDENSITY PEAK"
        case .acRMS: declaration = "ACCURRENTDENSITY RMS"
        }
        return "  \(declaration) \(limit.quantity.value) ;"
    }
}
