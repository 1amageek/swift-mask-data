import TechIR

/// Retains exact opposing overhang pairs and adjacent-layer direction.
enum LEFLayerEnclosureCodec {
    static func read(_ tokens: [String], from start: Int) throws -> (enclosure: IRTechLayerEnclosure, next: Int) {
        guard let end = tokens[(start + 1)...].firstIndex(of: ";") else {
            throw LEFError.missingSemicolon(command: "ENCLOSURE")
        }
        var index = start + 1
        var side: IRTechLayerEnclosure.Side?
        if index < end, let value = IRTechLayerEnclosure.Side(rawValue: tokens[index].lowercased()) {
            side = value
            index += 1
        }
        for token in tokens[index..<end] where ["WIDTH", "LENGTH", "EXCEPTEXTRACUT"].contains(token.uppercased()) {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Conditional layer enclosures lack retained
            // selectors. Production LEF preflight refuses them until source/writer/
            // projection contracts and exact geometric selection are implemented.
            throw LEFError.unsupportedCommand("ENCLOSURE \(token.uppercased()) in LAYER")
        }
        guard end - index == 2, let first = Double(tokens[index]), let second = Double(tokens[index + 1]) else {
            throw LEFError.invalidStructure("ENCLOSURE requires optional ABOVE/BELOW and two overhangs")
        }
        let enclosure = IRTechLayerEnclosure(overhang1: first, overhang2: second, side: side)
        try validate([enclosure], layerType: .cut)
        return (enclosure, end + 1)
    }

    static func validate(_ enclosures: [IRTechLayerEnclosure], layerType: LEFLayerDef.LayerType) throws {
        guard enclosures.isEmpty || layerType == .cut else {
            throw LEFError.invalidStructure("Layer ENCLOSURE requires CUT")
        }
        for enclosure in enclosures {
            guard enclosure.overhang1.isFinite, enclosure.overhang2.isFinite else {
                throw LEFError.invalidNumber(command: "ENCLOSURE", value: "non-finite")
            }
        }
    }

    static func write(_ enclosure: IRTechLayerEnclosure) -> String {
        let qualifier = enclosure.side.map { $0.rawValue.uppercased() + " " } ?? ""
        return "  ENCLOSURE \(qualifier)\(enclosure.overhang1) \(enclosure.overhang2) ;"
    }
}
