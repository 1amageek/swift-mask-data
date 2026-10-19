import Foundation
import Testing
import LEF
import TechIR

@Suite("LEF exact layer enclosures", .timeLimit(.minutes(1)))
struct LEFLayerEnclosureTests {
    private func read(_ body: String, type: String = "CUT") throws -> LEFDocument {
        try LEFLibraryReader.read(Data("VERSION 5.8 ; LAYER V TYPE \(type) ; \(body) END V END LIBRARY".utf8))
    }

    @Test func orderedDirectionalAndAlternativePairsRoundTrip() throws {
        let document = try read("""
        ENCLOSURE BELOW 0 0 ; ENCLOSURE ABOVE 0.03 0.06 ;
        ENCLOSURE ABOVE 0.04 0.01 ; ENCLOSURE 0.02 0.02 ; ENCLOSURE -0.01 0.03 ;
        """)
        let expected: [IRTechLayerEnclosure] = [
            .init(overhang1: 0, overhang2: 0, side: .below),
            .init(overhang1: 0.03, overhang2: 0.06, side: .above),
            .init(overhang1: 0.04, overhang2: 0.01, side: .above),
            .init(overhang1: 0.02, overhang2: 0.02), .init(overhang1: -0.01, overhang2: 0.03)]
        #expect(document.layers[0].enclosures == expected)
        #expect(document.layers[0].enclosure == nil)
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
        #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document)) == document)
        let library = try LEFTechIRConverter.toIRTechLibrary(document)
        #expect(library.layers[0].enclosures == expected)
        #expect(library.enclosureRules.isEmpty)
        #expect(LEFTechIRConverter.toLEFDocument(library).layers[0].enclosures == expected)
        #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(library)) == library)
    }

    @Test func legacySingleViewDoesNotFlattenOtherRules() throws {
        var layer = try read("ENCLOSURE 0.03 0.06 ;").layers[0]
        #expect(layer.enclosure == LEFEnclosure(overhang1: 0.03, overhang2: 0.06))
        layer.enclosures.append(.init(overhang1: 0.05, overhang2: 0.07, side: .above))
        #expect(layer.enclosure == nil)
        layer.enclosure = LEFEnclosure(overhang1: 0.1, overhang2: 0.2)
        #expect(layer.enclosures == [.init(overhang1: 0.1, overhang2: 0.2), .init(overhang1: 0.05, overhang2: 0.07, side: .above)])
        layer.enclosure = nil
        #expect(layer.enclosures == [.init(overhang1: 0.05, overhang2: 0.07, side: .above)])
        #expect(layer.enclosure == nil)
        let initialized = LEFLayerDef(name: "V", type: .cut, enclosure: .init(overhang1: 0, overhang2: 0),
                                     enclosures: layer.enclosures)
        #expect(initialized.enclosures.count == 2)
    }

    @Test func symmetricPairsDoNotInventAdjacentLayerIdentity() throws {
        let library = try LEFTechIRConverter.toIRTechLibrary(read("ENCLOSURE 0.05 0.05 ;"))
        #expect(library.layers[0].enclosures == [.init(overhang1: 0.05, overhang2: 0.05)])
        #expect(library.enclosureRules.isEmpty)
    }

    @Test(arguments: ["ENCLOSURE ;", "ENCLOSURE ABOVE ;", "ENCLOSURE BELOW 0.1 ;", "ENCLOSURE ABOVE BELOW 0.1 0.2 ;",
        "ENCLOSURE SIDE 0.1 0.2 ;", "ENCLOSURE 0.1 0.2 0.3 ;", "ENCLOSURE 0.1 nan ;", "ENCLOSURE inf 0.2 ;",
        "ENCLOSURE BELOW 0.1 0.2 extra ;", "ENCLOSURE ABOVE 0.1 0.2"])
    func malformedSource(_ body: String) {
        #expect(throws: LEFError.self) { _ = try read(body) }
    }

    @Test(arguments: ["WIDTH", "LENGTH", "EXCEPTEXTRACUT"])
    func unsupportedConditionIsExplicit(_ qualifier: String) {
        #expect(throws: LEFError.unsupportedCommand("ENCLOSURE \(qualifier) in LAYER")) {
            _ = try read("ENCLOSURE ABOVE 0.1 0.2 \(qualifier) 0.3 ;")
        }
    }

    @Test func sourceWriterAndProjectionRejectInvalidContextsAndValues() throws {
        for type in ["ROUTING", "MASTERSLICE", "OVERLAP", "IMPLANT"] {
            #expect(throws: LEFError.self) { _ = try read("ENCLOSURE ABOVE 0.1 0.2 ;", type: type) }
        }
        var document = try read("ENCLOSURE 0.1 0.2 ;")
        document.layers[0].enclosures[0].overhang1 = .infinity
        #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(document) }
        #expect(throws: LEFError.self) { _ = try LEFTechIRConverter.toIRTechLibrary(document) }
        document = try read("ENCLOSURE 0.1 0.2 ;")
        var library = try LEFTechIRConverter.toIRTechLibrary(document)
        library.layers[0].type = .routing
        let restored = LEFTechIRConverter.toLEFDocument(library)
        #expect(restored.layers[0].enclosures == document.layers[0].enclosures)
        #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(restored) }
    }

    @Test func legacyJSONMigrationAndDualKeyConflict() throws {
        let layer = try read("ENCLOSURE 0.1 0.2 ;").layers[0]
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(layer)) as? [String: Any])
        #expect(json["enclosure"] == nil)
        json.removeValue(forKey: "enclosures")
        json["enclosure"] = ["overhang1": 0.1, "overhang2": 0.2]
        func decode(_ object: [String: Any]) throws -> LEFLayerDef {
            try JSONDecoder().decode(LEFLayerDef.self, from: JSONSerialization.data(withJSONObject: object))
        }
        #expect(try decode(json).enclosures == layer.enclosures)
        json["enclosures"] = [["overhang1": 0.1, "overhang2": 0.2]]
        #expect(try decode(json).enclosures == layer.enclosures)
        json["enclosures"] = [["overhang1": 0.3, "overhang2": 0.4, "side": "above"]]
        #expect(throws: DecodingError.self) { _ = try decode(json) }
        json["enclosures"] = []
        #expect(throws: DecodingError.self) { _ = try decode(json) }
        json.removeValue(forKey: "enclosures"); json.removeValue(forKey: "enclosure")
        #expect(try decode(json).enclosures.isEmpty)
        let library = try LEFTechIRConverter.toIRTechLibrary(read(""))
        json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(library.layers[0])) as? [String: Any])
        json.removeValue(forKey: "enclosures")
        #expect(try JSONDecoder().decode(IRTechLayerDef.self, from: JSONSerialization.data(withJSONObject: json)).enclosures.isEmpty)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LEF_REAL_TECHLEF_DIRECTORY"] != nil))
    func unchangedActualSourcePrefixAndFullSourceFacts() throws {
        let directory = try #require(ProcessInfo.processInfo.environment["LEF_REAL_TECHLEF_DIRECTORY"])
        for corner in ["nom", "min", "max"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("sky130_fd_sc_hd__\(corner).tlef")
            let data = try Data(contentsOf: url)
            let source = try #require(String(data: data, encoding: .utf8))
            let mcon = try #require(source.range(of: "LAYER mcon"))
            let next = try #require(source.range(of: "  RESISTANCE", range: mcon.upperBound..<source.endIndex))
            let prefix = Data((source[..<next.lowerBound] + "\nEND mcon\nEND LIBRARY\n").utf8)
            let document = try LEFLibraryReader.read(prefix)
            let layer = try #require(document.layers.first(where: { $0.name == "mcon" }))
            #expect(layer.enclosures == [.init(overhang1: 0, overhang2: 0, side: .below), .init(overhang1: 0.03, overhang2: 0.06, side: .above)])
            #expect(layer.enclosure == nil)
            #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
            #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document)) == document)
            let library = try LEFTechIRConverter.toIRTechLibrary(document)
            #expect(library.enclosureRules.isEmpty)
            #expect(library.layers.first(where: { $0.name == "mcon" })?.enclosures == layer.enclosures)
            #expect(LEFTechIRConverter.toLEFDocument(library).layers.first(where: { $0.name == "mcon" })?.enclosures == layer.enclosures)
            #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(library)) == library)
            #expect(try LEFLibraryReader.read(data).viaGenerationRules.count == 25)
        }
    }
}
