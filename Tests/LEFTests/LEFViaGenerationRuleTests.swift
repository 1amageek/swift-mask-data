import Foundation
import Testing
import LEF
import TechIR

@Suite("LEF via generation formulas", .timeLimit(.minutes(1)))
struct LEFViaGenerationRuleTests {
    private let layers = "LAYER M1 TYPE ROUTING ; END M1 LAYER M2 TYPE ROUTING ; END M2 LAYER C TYPE CUT ; END C"
    private let formula = """
    VIARULE R GENERATE
      LAYER M1 ; ENCLOSURE 0.06 0.03 ;
      LAYER M2 ; ENCLOSURE -0.01 0.04 ;
      LAYER C ; RECT -0.1 -0.2 0.3 0.4 ; SPACING 0.5 BY 0.8 ;
    END R
    """

    private func read(_ body: String, declarations: String? = nil) throws -> LEFDocument {
        try LEFLibraryReader.read(Data("\(declarations ?? layers)\n\(body)\nEND LIBRARY".utf8))
    }

    @Test func exactFormulaRoundTripsWithoutInstantiatingGeometry() throws {
        let document = try read(formula)
        let rule = try #require(document.viaGenerationRules.first)
        #expect(document.vias.isEmpty)
        #expect(rule.name == "R")
        #expect(rule.routingLayers.map(\.layerName) == ["M1", "M2"])
        #expect(rule.routingLayers[0].enclosure == .init(overhang1: 0.06, overhang2: 0.03))
        #expect(rule.routingLayers[1].enclosure == .init(overhang1: -0.01, overhang2: 0.04))
        #expect(rule.cutLayerName == "C")
        #expect(rule.cutRectangle == .init(x1: -0.1, y1: -0.2, x2: 0.3, y2: 0.4))
        #expect(rule.cutCenterSpacing == .xy(x: 0.5, y: 0.8))
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
        #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document)) == document)
        let library = try LEFTechIRConverter.toIRTechLibrary(document)
        #expect(library.viaGenerationRules == document.viaGenerationRules)
        #expect(library.vias.isEmpty)
        #expect(LEFTechIRConverter.toLEFDocument(library).viaGenerationRules == document.viaGenerationRules)
        #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(library)) == library)
        let precise = try LEFLibraryReader.read(Data("UNITS DATABASE MICRONS 20000 ; END UNITS\n\(layers)\n\(formula)\nEND LIBRARY".utf8))
        #expect(precise.viaGenerationRules == document.viaGenerationRules)
    }

    @Test func fixedViaAndRuleNamespacesAndSourceOrderRemainIndependent() throws {
        let second = formula.replacingOccurrences(of: "VIARULE R ", with: "VIARULE S ").replacingOccurrences(of: "END R", with: "END S")
        let fixed = "VIA R DEFAULT LAYER C ; RECT -0.1 -0.1 0.1 0.1 ; LAYER M1 ; RECT -0.2 -0.2 0.2 0.2 ; LAYER M2 ; RECT -0.3 -0.3 0.3 0.3 ; END R"
        let document = try read(formula + "\n" + fixed + "\n" + second)
        #expect(document.vias.count == 1)
        #expect(document.vias[0].isDefault)
        #expect(document.viaGenerationRules.map(\.name) == ["R", "S"])
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
    }

    @Test func legacyRootsDecodeEmpty() throws {
        let document = try read("")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
        json.removeValue(forKey: "viaGenerationRules")
        #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONSerialization.data(withJSONObject: json)).viaGenerationRules.isEmpty)
        let library = try LEFTechIRConverter.toIRTechLibrary(document)
        json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as? [String: Any])
        json.removeValue(forKey: "viaGenerationRules")
        #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONSerialization.data(withJSONObject: json)).viaGenerationRules.isEmpty)
    }

    @Test(arguments: ["DEFAULT", "WIDTH", "RESISTANCE", "PROPERTY", "DIRECTION", "OVERHANG", "METALOVERHANG"])
    func optionalAndLegacyVariantsAreExplicitlyRefused(_ command: String) {
        let source: String
        switch command {
        case "DEFAULT": source = formula.replacingOccurrences(of: "GENERATE", with: "GENERATE DEFAULT")
        case "WIDTH": source = formula.replacingOccurrences(of: "ENCLOSURE 0.06 0.03 ;", with: "ENCLOSURE 0.06 0.03 ; WIDTH 0.1 TO 1 ;")
        case "RESISTANCE": source = formula.replacingOccurrences(of: "END R", with: "RESISTANCE 20 ; END R")
        case "PROPERTY": source = formula.replacingOccurrences(of: "END R", with: "PROPERTY p 1 ; END R")
        default: source = formula.replacingOccurrences(of: "ENCLOSURE 0.06 0.03 ;", with: "\(command) 1 ;")
        }
        #expect(throws: LEFError.unsupportedCommand("\(command) in VIARULE GENERATE")) { _ = try read(source) }
    }

    @Test func otherRuleFormsAndRuleContextsRefuse() {
        #expect(throws: LEFError.unsupportedCommand("VIARULE without GENERATE")) {
            _ = try read(formula.replacingOccurrences(of: " GENERATE", with: ""))
        }
        #expect(throws: LEFError.self) { _ = try read(formula.replacingOccurrences(of: "R GENERATE", with: "DEFAULT GENERATE")) }
        #expect(throws: LEFError.self) {
            _ = try LEFLibraryReader.read(Data("LAYER M1 TYPE ROUTING ; \(formula) END M1 END LIBRARY".utf8))
        }
    }

    @Test(arguments: [
        ("END R", "END S"), ("END R", ""), ("LAYER M2 ; ENCLOSURE -0.01 0.04 ;", ""),
        ("LAYER M2", "LAYER M1"), ("LAYER C", "LAYER M2"), ("LAYER C", "LAYER missing"),
        ("ENCLOSURE 0.06 0.03", "ENCLOSURE 0.06"), ("ENCLOSURE 0.06 0.03", "ENCLOSURE nan 0.03"),
        ("RECT -0.1 -0.2 0.3 0.4", "RECT -0.1 -0.2 -0.1 0.4"),
        ("RECT -0.1 -0.2 0.3 0.4", "RECT inf -0.2 0.3 0.4"),
        ("SPACING 0.5 BY 0.8", "SPACING 0.5 0.8"), ("SPACING 0.5 BY 0.8", "SPACING 0 BY 0.8"),
        ("SPACING 0.5 BY 0.8", "SPACING -0.5 BY 0.8"), ("SPACING 0.5 BY 0.8", "SPACING 0.5 BY nan"),
        ("SPACING 0.5 BY 0.8 ;", "SPACING 0.5 BY 0.8"), ("LAYER M1 ;", "LAYER M1"),
        ("LAYER C ;", "LAYER C ; ENCLOSURE 0 0 ;"), ("END R", "LAYER M1 ; END R")])
    func malformedOrUnresolvedSourceRefuses(_ original: String, _ replacement: String) {
        #expect(throws: LEFError.self) { _ = try read(formula.replacingOccurrences(of: original, with: replacement)) }
    }

    @Test func duplicateNamesAndWrongLayerTypesRefuse() {
        #expect(throws: LEFError.self) { _ = try read(formula + "\n" + formula) }
        for declarations in [layers + " LAYER M1 TYPE ROUTING ; END M1",
            layers.replacingOccurrences(of: "M1 TYPE ROUTING", with: "M1 TYPE CUT"),
            layers.replacingOccurrences(of: "C TYPE CUT", with: "C TYPE ROUTING"),
            layers.replacingOccurrences(of: "M2 TYPE ROUTING", with: "M2 TYPE MASTERSLICE")] {
            #expect(throws: LEFError.self) { _ = try read(formula, declarations: declarations) }
        }
    }

    @Test func invalidRawValuesAndReverseProjectionPreserveRefusableFacts() throws {
        let valid = try read(formula)
        let base = try #require(valid.viaGenerationRules.first)
        var cases: [IRTechViaGenerationRule] = []
        var bad = base; bad.cutCenterSpacing = .scalar(0.5); cases.append(bad)
        bad = base; bad.cutCenterSpacing = .xy(x: 0.5, y: -.infinity); cases.append(bad)
        bad = base; bad.cutRectangle.x2 = bad.cutRectangle.x1; cases.append(bad)
        bad = base; bad.routingLayers[0].enclosure.overhang1 = .nan; cases.append(bad)
        bad = base; bad.routingLayers.removeLast(); cases.append(bad)
        bad = base; bad.routingLayers[0].layerName = "missing"; cases.append(bad)
        bad = base; bad.name = "injected ;"; cases.append(bad)
        for rule in cases {
            var document = valid; document.viaGenerationRules = [rule]
            #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(document) }
            #expect(throws: LEFError.self) { _ = try LEFTechIRConverter.toIRTechLibrary(document) }
            var library = try LEFTechIRConverter.toIRTechLibrary(valid); library.viaGenerationRules = [rule]
            let reversed = LEFTechIRConverter.toLEFDocument(library)
            #expect(reversed.viaGenerationRules.count == 1)
            #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(reversed) }
        }
        var document = valid; document.viaGenerationRules.append(base)
        let raw = try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document))
        #expect(raw.viaGenerationRules == [base, base])
        #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(raw) }
        #expect(throws: LEFError.self) { _ = try LEFTechIRConverter.toIRTechLibrary(raw) }
        var library = try LEFTechIRConverter.toIRTechLibrary(valid); library.viaGenerationRules.append(base)
        #expect(LEFTechIRConverter.toLEFDocument(library).viaGenerationRules == [base, base])
        #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(LEFTechIRConverter.toLEFDocument(library)) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LEF_REAL_TECHLEF_DIRECTORY"] != nil))
    func unchangedOriginalPrefixAndFullFormulaFacts() throws {
        let directory = try #require(ProcessInfo.processInfo.environment["LEF_REAL_TECHLEF_DIRECTORY"])
        for corner in ["nom", "min", "max"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent("sky130_fd_sc_hd__\(corner).tlef"))
            let source = try #require(String(data: data, encoding: .utf8))
            let start = try #require(source.range(of: "VIARULE L1M1_PR GENERATE"))
            let end = try #require(source.range(of: "END L1M1_PR", range: start.upperBound..<source.endIndex))
            let prefix = try readOriginal(Data((source[..<end.upperBound] + "\nEND LIBRARY\n").utf8))
            #expect(prefix.viaGenerationRules.count == 1)
            let document = try readOriginal(data)
            #expect(document.viaGenerationRules.count == 25)
            #expect(document.vias.count == 25)
            #expect(document.viaGenerationRules.first == prefix.viaGenerationRules.first)
            let first = try #require(document.viaGenerationRules.first)
            #expect(first.name == "L1M1_PR")
            #expect(first.routingLayers.map(\.layerName) == ["li1", "met1"])
            #expect(first.routingLayers[0].enclosure == .init(overhang1: 0, overhang2: 0))
            #expect(first.routingLayers[1].enclosure == .init(overhang1: 0.06, overhang2: 0.03))
            #expect(first.cutLayerName == "mcon")
            #expect(first.cutRectangle == .init(x1: -0.085, y1: -0.085, x2: 0.085, y2: 0.085))
            #expect(first.cutCenterSpacing == .xy(x: 0.36, y: 0.36))
            if let output = ProcessInfo.processInfo.environment["LEF_VIA_GENERATION_EVIDENCE_DIRECTORY"] {
                let directory = URL(fileURLWithPath: output)
                try LEFLibraryWriter.write(document).write(to: directory.appendingPathComponent("lef-via-generation-\(corner)-written.lef"))
                let library = try LEFTechIRConverter.toIRTechLibrary(document)
                try JSONEncoder().encode(library).write(to: directory.appendingPathComponent("lef-via-generation-\(corner)-techir.json"))
            }
        }
    }

    private func readOriginal(_ data: Data) throws -> LEFDocument {
        let document = try LEFLibraryReader.read(data)
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
        #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document)) == document)
        let library = try LEFTechIRConverter.toIRTechLibrary(document)
        #expect(library.viaGenerationRules == document.viaGenerationRules)
        #expect(LEFTechIRConverter.toLEFDocument(library).viaGenerationRules == document.viaGenerationRules)
        #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(library)) == library)
        return document
    }
}
