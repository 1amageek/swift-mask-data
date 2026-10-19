import Foundation
import Testing
import LEF
import TechIR

@Suite("LEF property definitions", .timeLimit(.minutes(1)))
struct LEFPropertyDefinitionTests {
    private func read(_ body: String) throws -> LEFDocument {
        try LEFLibraryReader.read(Data("VERSION 5.8 ; PROPERTYDEFINITIONS \(body) END PROPERTYDEFINITIONS END LIBRARY".utf8))
    }

    @Test func roundTrip() throws {
        let document = try read("""
        LAYER LEF58_TYPE STRING ;
        LIBRARY title STRING "Process #1 ; END" ;
        LIBRARY count INTEGER RANGE -9223372036854775808 9223372036854775807 9223372036854775807 ;
        LIBRARY voltage REAL RANGE 0.1 5e0 1.8 ;
        MACRO count INTEGER RANGE 1 10 ;
        NONDEFAULTRULE rule STRING ; PIN pin REAL ; VIA via INTEGER ; VIARULE via STRING ;
        """)
        #expect(document.propertyDefinitions.count == 9)
        #expect(document.propertyDefinitions[1].libraryValue == "Process #1 ; END")
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)).propertyDefinitions == document.propertyDefinitions)
        #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document)) == document)
        let library = try LEFTechIRConverter.toIRTechLibrary(document)
        #expect(library.propertyDefinitions == document.propertyDefinitions)
        #expect(LEFTechIRConverter.toLEFDocument(library).propertyDefinitions == document.propertyDefinitions)
        #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(library)) == library)
    }

    @Test(arguments: ["LAYER p STRING RANGE 0 1 ;", "LAYER p BOOLEAN ;", "NET p STRING ;",
        "LAYER p STRING \"value\" ;", "LIBRARY p INTEGER RANGE 2 1 ;", "LIBRARY p REAL RANGE 0 inf ;",
        "LIBRARY p INTEGER 1.5 ;", "LIBRARY p INTEGER 9223372036854775808 ;", "LIBRARY p REAL nan ;",
        "LIBRARY p INTEGER RANGE 1 2 3 ;", "LIBRARY p REAL RANGE 1 2 0.9 ;", "LIBRARY p STRING unquoted ;",
        "LAYER p STRING ; LAYER p REAL ;", "LAYER p STRING extra more ;", "LAYER p STRING"])
    func malformed(_ body: String) {
        #expect(throws: LEFError.self) { _ = try read(body) }
    }

    @Test(arguments: ["MACRO M PROPERTYDEFINITIONS LAYER p STRING ; END PROPERTYDEFINITIONS END M",
        "PROPERTYDEFINITIONS LAYER p STRING ; END PROPERTYDEFINITIONS PROPERTYDEFINITIONS END PROPERTYDEFINITIONS",
        "UNITS PROPERTYDEFINITIONS END PROPERTYDEFINITIONS END UNITS"])
    func context(_ source: String) {
        #expect(throws: LEFError.self) { _ = try LEFLibraryReader.read(Data("VERSION 5.8 ; \(source) END LIBRARY".utf8)) }
    }

    @Test func writerRejectsAndLegacyDefaults() throws {
        var document = try read("LAYER p STRING ;")
        document.propertyDefinitions[0].range = .init(lower: "0", upper: "1")
        #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(document) }
        #expect(throws: LEFError.self) { _ = try LEFTechIRConverter.toIRTechLibrary(document) }
        document.propertyDefinitions = []
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
        json.removeValue(forKey: "propertyDefinitions")
        #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONSerialization.data(withJSONObject: json)).propertyDefinitions.isEmpty)
        let library = try LEFTechIRConverter.toIRTechLibrary(document)
        json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as? [String: Any])
        json.removeValue(forKey: "propertyDefinitions")
        #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONSerialization.data(withJSONObject: json)).propertyDefinitions.isEmpty)
    }

    @Test func declarationDoesNotEnableUnknownLayerRules() {
        #expect(throws: LEFError.self) {
            _ = try LEFLibraryReader.read(Data("VERSION 5.8 ; PROPERTYDEFINITIONS LAYER LEF58_TYPE STRING ; END PROPERTYDEFINITIONS LAYER nwell TYPE MASTERSLICE ; PROPERTY LEF58_TYPE \"TYPE UNKNOWN ;\" ; END nwell END LIBRARY".utf8))
        }
    }
}
