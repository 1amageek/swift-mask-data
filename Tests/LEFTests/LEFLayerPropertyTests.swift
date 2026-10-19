import Foundation
import Testing
import LEF
import TechIR

@Suite("LEF layer properties", .timeLimit(.minutes(1)))
struct LEFLayerPropertyTests {
    private func read(_ assignments: String, definitions: String = "LAYER LEF58_TYPE STRING ;", type: String = "MASTERSLICE") throws -> LEFDocument {
        try LEFLibraryReader.read(Data("VERSION 5.8 ; PROPERTYDEFINITIONS \(definitions) END PROPERTYDEFINITIONS LAYER L TYPE \(type) ; \(assignments) END L END LIBRARY".utf8))
    }

    @Test(arguments: [("NWELL", IRTechLayerSubtype.nwell), ("PWELL", .pwell),
        ("ABOVEDIEEDGE", .aboveDieEdge), ("BELOWDIEEDGE", .belowDieEdge), ("DIFFUSION", .diffusion),
        ("TRIMPOLY", .trimPoly), ("TRIMMETAL", .trimMetal), ("REGION", .region), ("POLYROUTING", .polyRouting)])
    func subtypeRoundTrip(_ name: String, _ subtype: IRTechLayerSubtype) throws {
        let document = try read("PROPERTY LEF58_TYPE \"TYPE \(name) ;\" ;", type: subtype == .polyRouting ? "ROUTING" : "MASTERSLICE")
        #expect(document.layers[0].subtype == subtype)
        #expect(document.layers[0].properties == [.init(name: "LEF58_TYPE", value: .string("TYPE \(name) ;"))])
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)).layers == document.layers)
        #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document)) == document)
        let library = try LEFTechIRConverter.toIRTechLibrary(document)
        #expect(library.layers[0].properties == document.layers[0].properties)
        #expect(library.layers[0].subtype == subtype)
        #expect(LEFTechIRConverter.toLEFDocument(library).layers == document.layers)
        #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(library)) == library)
    }

    @Test func typedValuesRemainExact() throws {
        let document = try read("""
        PROPERTY i 9223372036854775807 ; PROPERTY r 1.25e-3 ; PROPERTY s "Process #1 ; END" ;
        """, definitions: "LAYER i INTEGER RANGE -9223372036854775808 9223372036854775807 ; LAYER r REAL RANGE 0 1 ; LAYER s STRING ;")
        let properties = document.layers[0].properties
        #expect(properties.map(\.value) == [.integer("9223372036854775807"), .real("1.25e-3"), .string("Process #1 ; END")])
        #expect(document.layers[0].subtype == nil)
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)).layers[0].properties == properties)
        #expect(LEFTechIRConverter.toLEFDocument(try LEFTechIRConverter.toIRTechLibrary(document)).layers[0].properties == properties)
    }

    @Test(arguments: ["PROPERTY missing 1 ;", "PROPERTY LEF58_TYPE TYPE ;", "PROPERTY LEF58_TYPE \"TYPE UNKNOWN ;\" ;",
        "PROPERTY LEF58_TYPE \"TYPE NWELL\" ;", "PROPERTY LEF58_TYPE \"TYPE NWELL ; extra\" ;",
        "PROPERTY LEF58_TYPE \"TYPE NWELL ;\" extra ;", "PROPERTY LEF58_TYPE \"TYPE NWELL ;\" ; PROPERTY LEF58_TYPE \"TYPE PWELL ;\" ;",
        "PROPERTY LEF58_TYPE ;"])
    func invalidAssignment(_ source: String) {
        #expect(throws: LEFError.self) { _ = try read(source) }
    }

    @Test(arguments: ["1.5", "9223372036854775808", "\"1\"", "2", "nan"])
    func invalidInteger(_ value: String) {
        #expect(throws: LEFError.self) { _ = try read("PROPERTY p \(value) ;", definitions: "LAYER p INTEGER RANGE -1 1 ;") }
    }

    @Test(arguments: ["nan", "inf", "\"0.5\"", "2"])
    func invalidReal(_ value: String) {
        #expect(throws: LEFError.self) { _ = try read("PROPERTY p \(value) ;", definitions: "LAYER p REAL RANGE 0 1 ;") }
    }

    @Test(arguments: ["ROUTING", "CUT", "OVERLAP", "IMPLANT"])
    func invalidBaseLayer(_ type: String) {
        #expect(throws: LEFError.self) { _ = try read("PROPERTY LEF58_TYPE \"TYPE NWELL ;\" ;", type: type) }
    }

    @Test func wrongDeclarationAndContextAreRefused() {
        for definitions in ["MACRO LEF58_TYPE STRING ;", "LAYER LEF58_TYPE INTEGER ;"] {
            #expect(throws: LEFError.self) { _ = try read("PROPERTY LEF58_TYPE \"TYPE NWELL ;\" ;", definitions: definitions) }
        }
        #expect(throws: LEFError.self) { _ = try read("PROPERTY LEF58_TYPE \"TYPE POLYROUTING ;\" ;") }
        #expect(throws: LEFError.self) { _ = try read("PROPERTY LEF58_TYPE \"TYPE NWELL ;\"") }
        #expect(throws: LEFError.self) {
            _ = try LEFLibraryReader.read(Data("LAYER L TYPE MASTERSLICE ; PROPERTY LEF58_TYPE \"TYPE NWELL ;\" ; END L PROPERTYDEFINITIONS LAYER LEF58_TYPE STRING ; END PROPERTYDEFINITIONS END LIBRARY".utf8))
        }
    }

    @Test func unknownPropertyRetentionIsNotTypeAdmission() throws {
        let document = try read("PROPERTY LEF58_UNKNOWN \"RULE unimplemented ;\" ;", definitions: "LAYER LEF58_UNKNOWN STRING ;")
        #expect(document.layers[0].subtype == nil)
        #expect(document.layers[0].properties[0].name == "LEF58_UNKNOWN")
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
    }

    @Test func programmaticContradictionsAreRefused() throws {
        let source = try read("PROPERTY LEF58_TYPE \"TYPE NWELL ;\" ;")
        var documents: [LEFDocument] = []
        var value = source; value.layers[0].subtype = .pwell; documents.append(value)
        value = source; value.layers[0].properties = []; documents.append(value)
        value = source; value.propertyDefinitions = []; documents.append(value)
        value = source; value.layers[0].properties[0].value = .integer("1"); documents.append(value)
        value = source; value.layers[0].properties[0].value = .string("TYPE UNKNOWN ;"); documents.append(value)
        for document in documents {
            #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(document) }
            #expect(throws: LEFError.self) { _ = try LEFTechIRConverter.toIRTechLibrary(document) }
        }
        var library = try LEFTechIRConverter.toIRTechLibrary(source)
        library.layers[0].subtype = .pwell
        let restored = LEFTechIRConverter.toLEFDocument(library)
        #expect(restored.layers[0].subtype == .pwell)
        #expect(restored.layers[0].properties == source.layers[0].properties)
        #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(restored) }
    }

    @Test func legacyLayersDefaultAbsent() throws {
        let document = try read("")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(document.layers[0])) as? [String: Any])
        json.removeValue(forKey: "properties"); json.removeValue(forKey: "subtype")
        let layer = try JSONDecoder().decode(LEFLayerDef.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(layer.properties.isEmpty && layer.subtype == nil)
        let library = try LEFTechIRConverter.toIRTechLibrary(document)
        json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(library.layers[0])) as? [String: Any])
        json.removeValue(forKey: "properties"); json.removeValue(forKey: "subtype")
        let ir = try JSONDecoder().decode(IRTechLayerDef.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(ir.properties.isEmpty && ir.subtype == nil)
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LEF_REAL_TECHLEF_DIRECTORY"] != nil))
    func unchangedRealTechnologyPrefixesAndFullSourceFormulaFacts() throws {
        let directory = try #require(ProcessInfo.processInfo.environment["LEF_REAL_TECHLEF_DIRECTORY"])
        for corner in ["nom", "min", "max"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("sky130_fd_sc_hd__\(corner).tlef")
            let data = try Data(contentsOf: url)
            let source = try #require(String(data: data, encoding: .utf8))
            let end = try #require(source.range(of: "END pwell"))
            let prefix = Data((source[..<end.upperBound] + "\nEND LIBRARY\n").utf8)
            let document = try LEFLibraryReader.read(prefix)
            #expect(document.layers.map(\.name) == ["nwell", "pwell"])
            #expect(document.layers.map(\.subtype) == [.nwell, .pwell])
            #expect(document.propertyDefinitions == [.init(objectType: .layer, name: "LEF58_TYPE", valueType: .string)])
            #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
            let library = try LEFTechIRConverter.toIRTechLibrary(document)
            #expect(LEFTechIRConverter.toLEFDocument(library).layers == document.layers)
            #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document)) == document)
            #expect(try LEFLibraryReader.read(data).viaGenerationRules.count == 25)
        }
    }

}
