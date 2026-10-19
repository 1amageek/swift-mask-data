import Foundation
import Testing
import LEF
import TechIR

@Suite("LEF distinct layer resistance", .timeLimit(.minutes(1)))
struct LEFLayerResistanceTests {
    private func read(_ declaration: String, type: String = "CUT") throws -> LEFDocument {
        try LEFLibraryReader.read(Data("VERSION 5.8 ; LAYER L TYPE \(type) ; \(declaration) END L END LIBRARY".utf8))
    }

    @Test(arguments: [0.0, 1.6, 9.3, 23.0])
    func cutScalarRoundTrip(_ resistance: Double) throws {
        let document = try read("RESISTANCE \(resistance) ;")
        #expect(document.layers[0].cutResistanceOhms == resistance)
        #expect(document.layers[0].resistance == nil)
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
        #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document)) == document)
        let library = try LEFTechIRConverter.toIRTechLibrary(document)
        #expect(library.layers[0].cutResistanceOhms == resistance)
        #expect(library.layers[0].resistance == nil)
        #expect(LEFTechIRConverter.toLEFDocument(library).layers == document.layers)
        #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(library)) == library)
    }

    @Test func sheetCutAndViaQuantitiesStaySeparateWithoutPrecisionRescaling() throws {
        let document = try LEFLibraryReader.read(Data("""
        UNITS RESISTANCE OHMS 1000 ; END UNITS
        LAYER M TYPE ROUTING ; RESISTANCE RPERSQ 0.125 ; END M
        LAYER C TYPE CUT ; RESISTANCE 9.3 ; END C
        VIA V ; RESISTANCE 5 ; END V END LIBRARY
        """.utf8))
        #expect(document.layers[0].resistance == 0.125)
        #expect(document.layers[0].cutResistanceOhms == nil)
        #expect(document.layers[1].cutResistanceOhms == 9.3)
        #expect(document.layers[1].resistance == nil)
        #expect(document.vias[0].resistance == 5)
        let library = try LEFTechIRConverter.toIRTechLibrary(document)
        #expect(library.layers[1].cutResistanceOhms == 9.3)
        #expect(library.vias[0].resistance == 5)
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
    }

    @Test(arguments: ["RESISTANCE ;", "RESISTANCE -1 ;", "RESISTANCE nan ;", "RESISTANCE inf ;",
        "RESISTANCE 1 2 ;", "RESISTANCE OHMS 1 ;", "RESISTANCE PWL ((0 1)(1 2)) ;",
        "RESISTANCE 1 ; RESISTANCE 2 ;", "RESISTANCE 1"])
    func malformedCutSource(_ declaration: String) {
        #expect(throws: LEFError.self) { _ = try read(declaration) }
    }

    @Test func wrongLayerContextAndUnsupportedSheetLawAreRefused() {
        #expect(throws: LEFError.self) { _ = try read("RESISTANCE RPERSQ 1 ;") }
        #expect(throws: LEFError.self) { _ = try read("RESISTANCE 1 ;", type: "ROUTING") }
        for type in ["MASTERSLICE", "OVERLAP", "IMPLANT"] {
            #expect(throws: LEFError.self) { _ = try read("RESISTANCE 1 ;", type: type) }
            #expect(throws: LEFError.self) { _ = try read("RESISTANCE RPERSQ 1 ;", type: type) }
        }
        #expect(throws: LEFError.unsupportedCommand("RESISTANCE RPERSQ PWL in LAYER")) {
            _ = try read("RESISTANCE RPERSQ PWL ((0 1)(1 2)) ;", type: "ROUTING")
        }
    }

    @Test func invalidOwnedQuantitiesFailWriterAndForwardProjection() throws {
        let source = try read("RESISTANCE 1 ;")
        var documents: [LEFDocument] = []
        var document = source; document.layers[0].resistance = 1; documents.append(document)
        document = source; document.layers[0].type = .routing; documents.append(document)
        document = source; document.layers[0].cutResistanceOhms = -.infinity; documents.append(document)
        document = source; document.layers[0].cutResistanceOhms = -1; documents.append(document)
        document = source; document.layers[0].cutResistanceOhms = .nan; documents.append(document)
        for invalid in documents {
            #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(invalid) }
            #expect(throws: LEFError.self) { _ = try LEFTechIRConverter.toIRTechLibrary(invalid) }
        }
        var library = try LEFTechIRConverter.toIRTechLibrary(source)
        library.layers[0].resistance = 2
        let restored = LEFTechIRConverter.toLEFDocument(library)
        #expect(restored.layers[0].cutResistanceOhms == 1)
        #expect(restored.layers[0].resistance == 2)
        #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(restored) }
    }

    @Test func legacyResistanceIsNeverReinterpretedAsCutOhms() throws {
        let source = try read("RESISTANCE RPERSQ 0.5 ;", type: "ROUTING")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source.layers[0])) as? [String: Any])
        json.removeValue(forKey: "cutResistanceOhms")
        let layer = try JSONDecoder().decode(LEFLayerDef.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(layer.resistance == 0.5 && layer.cutResistanceOhms == nil)
        json["type"] = "CUT"
        let legacyCut = try JSONDecoder().decode(LEFLayerDef.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacyCut.resistance == 0.5 && legacyCut.cutResistanceOhms == nil)
        #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(LEFDocument(layers: [legacyCut])) }
        #expect(throws: LEFError.self) { _ = try LEFTechIRConverter.toIRTechLibrary(LEFDocument(layers: [legacyCut])) }
        let library = try LEFTechIRConverter.toIRTechLibrary(source)
        json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(library.layers[0])) as? [String: Any])
        json.removeValue(forKey: "cutResistanceOhms")
        let ir = try JSONDecoder().decode(IRTechLayerDef.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(ir.resistance == 0.5 && ir.cutResistanceOhms == nil)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LEF_REAL_TECHLEF_DIRECTORY"] != nil))
    func unchangedActualSourcePrefixAndFullSourceFacts() throws {
        let directory = try #require(ProcessInfo.processInfo.environment["LEF_REAL_TECHLEF_DIRECTORY"])
        for (corner, expected) in [("nom", 9.3), ("min", 1.6), ("max", 23.0)] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("sky130_fd_sc_hd__\(corner).tlef")
            let data = try Data(contentsOf: url)
            let source = try #require(String(data: data, encoding: .utf8))
            let next = try #require(source.range(of: "  DCCURRENTDENSITY"))
            let prefix = Data((source[..<next.lowerBound] + "\nEND mcon\nEND LIBRARY\n").utf8)
            let document = try LEFLibraryReader.read(prefix)
            let cut = try #require(document.layers.first(where: { $0.name == "mcon" }))
            #expect(cut.cutResistanceOhms == expected && cut.resistance == nil)
            #expect(cut.antennaStatements.count == 1)
            #expect(cut.enclosures.count == 2)
            #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
            #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document)) == document)
            let library = try LEFTechIRConverter.toIRTechLibrary(document)
            #expect(library.layers.first(where: { $0.name == "mcon" })?.cutResistanceOhms == expected)
            #expect(LEFTechIRConverter.toLEFDocument(library).layers.first(where: { $0.name == "mcon" })?.cutResistanceOhms == expected)
            #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(library)) == library)
            #expect(try LEFLibraryReader.read(data).viaGenerationRules.count == 25)
        }
    }
}
