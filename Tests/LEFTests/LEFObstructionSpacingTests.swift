import Foundation
import Testing
import TechIR
@testable import LEF

@Suite("LEF obstruction spacing policy", .timeLimit(.minutes(1)))
struct LEFObstructionSpacingTests {
    @Test(arguments: ["ON", "OFF"])
    func standardDeclaration(_ value: String) throws {
        let document = try LEFLibraryReader.read(Data("VERSION 5.8 ; USEMINSPACING OBS \(value) ; END LIBRARY".utf8))
        #expect(document.obstructionSpacingUsesMinimumWidth == (value == "ON"))
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
        #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document)) == document)
        let technology = try LEFTechIRConverter.toIRTechLibrary(document)
        #expect(technology.obstructionSpacingUsesMinimumWidth == document.obstructionSpacingUsesMinimumWidth)
        #expect(LEFTechIRConverter.toLEFDocument(technology) == document)
        #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(technology)) == technology)
    }
    @Test func absenceAndLegacyValuesStayUnspecified() throws {
        let document = try LEFLibraryReader.read(Data("VERSION 5.8 ; END LIBRARY".utf8))
        #expect(document.obstructionSpacingUsesMinimumWidth == nil)
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)).obstructionSpacingUsesMinimumWidth == nil)
        let library = try LEFTechIRConverter.toIRTechLibrary(document)
        #expect(library.obstructionSpacingUsesMinimumWidth == nil)
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
        legacy.removeValue(forKey: "obstructionSpacingUsesMinimumWidth")
        #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONSerialization.data(withJSONObject: legacy)).obstructionSpacingUsesMinimumWidth == nil)
        legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as? [String: Any])
        legacy.removeValue(forKey: "obstructionSpacingUsesMinimumWidth")
        #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONSerialization.data(withJSONObject: legacy)).obstructionSpacingUsesMinimumWidth == nil)
    }

    @Test(arguments: ["PIN ON", "OBS", "OBS MAYBE", "OBS ON OFF", "OBS 1"])
    func unsupportedGrammarFails(_ statement: String) {
        #expect(throws: LEFError.self) {
            try LEFLibraryReader.read(Data("VERSION 5.8 ; USEMINSPACING \(statement) ; END LIBRARY".utf8))
        }
    }

    @Test func duplicatesAndWrongContextFail() {
        for body in ["USEMINSPACING OBS ON ; USEMINSPACING OBS OFF ;", "USEMINSPACING OBS ON ; USEMINSPACING OBS ON ;",
                     "LAYER m1 TYPE ROUTING ; USEMINSPACING OBS ON ; END m1"] {
            #expect(throws: LEFError.self) { try LEFLibraryReader.read(Data("VERSION 5.8 ; \(body) END LIBRARY".utf8)) }
        }
    }

}
