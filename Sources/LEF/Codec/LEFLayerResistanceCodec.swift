/// Validates distinct routing sheet and individual cut resistance quantities.
enum LEFLayerResistanceCodec {
    static func validateValues(_ values: [String]) throws {
        if values.count >= 2, values[0].uppercased() == "RPERSQ", values[1].uppercased() == "PWL" {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Width-dependent routing resistance lacks
            // a retained law. LEF preflight refuses it until source/writer/projection
            // and electrical consumer evaluation are implemented and verified.
            throw LEFError.unsupportedCommand("RESISTANCE RPERSQ PWL in LAYER")
        }
        guard values.count == 1 || (values.count == 2 && values[0].uppercased() == "RPERSQ"),
              let token = values.last, let value = Double(token) else {
            throw LEFError.invalidStructure("Layer RESISTANCE requires a cut scalar or RPERSQ scalar")
        }
        try validateNumber(value)
    }

    static func validate(_ layer: LEFLayerDef) throws {
        if let sheet = layer.resistance {
            guard layer.type == .routing, layer.cutResistanceOhms == nil else {
                throw LEFError.invalidStructure("Sheet resistance requires ROUTING without per-cut resistance")
            }
            try validateNumber(sheet)
        }
        if let cut = layer.cutResistanceOhms {
            guard layer.type == .cut, layer.resistance == nil else {
                throw LEFError.invalidStructure("Per-cut resistance requires CUT without sheet resistance")
            }
            try validateNumber(cut)
        }
    }

    private static func validateNumber(_ value: Double) throws {
        guard value.isFinite, value >= 0 else {
            throw LEFError.invalidNumber(command: "RESISTANCE", value: String(value))
        }
    }
}
