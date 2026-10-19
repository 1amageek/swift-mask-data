/// Validates the unconditional hole-area profile without substituting metal island area.
enum LEFMinimumEnclosedAreaCodec {
    static func read(_ tokens: [String], from start: Int) throws -> (area: Double, next: Int) {
        guard let end = tokens[(start + 1)...].firstIndex(of: ";") else {
            throw LEFError.missingSemicolon(command: "MINENCLOSEDAREA")
        }
        let values = tokens[(start + 1)..<end]
        if values.contains(where: { $0.uppercased() == "WIDTH" }) {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Width-conditioned hole laws lack a
            // retained condition. Production preflight refuses WIDTH until source,
            // writer and exact conditional projection are implemented and verified.
            throw LEFError.unsupportedCommand("MINENCLOSEDAREA WIDTH")
        }
        guard values.count == 1, let token = values.first, let area = Double(token) else {
            throw LEFError.invalidStructure("MINENCLOSEDAREA requires one unqualified scalar")
        }
        try validateNumber(area)
        return (area, end + 1)
    }

    static func validate(_ layer: LEFLayerDef) throws {
        guard layer.minimumEnclosedAreas.isEmpty || layer.type == .routing else {
            throw LEFError.invalidStructure("MINENCLOSEDAREA requires ROUTING")
        }
        guard layer.minimumEnclosedAreas.count <= 1 else {
            throw LEFError.unsupportedCommand("repeated MINENCLOSEDAREA in LAYER")
        }
        for area in layer.minimumEnclosedAreas { try validateNumber(area) }
    }

    private static func validateNumber(_ area: Double) throws {
        guard area.isFinite, area >= 0 else {
            throw LEFError.invalidNumber(command: "MINENCLOSEDAREA", value: String(area))
        }
    }
}
