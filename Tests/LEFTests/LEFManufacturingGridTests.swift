import Foundation
import Testing
import TechIR
@testable import LEF

@Suite("LEF manufacturing grid", .timeLimit(.minutes(1)))
struct LEFManufacturingGridTests {
    @Test func sourceValueAndStandardRoundTrip() throws {
        let source = Data("VERSION 5.7 ; UNITS DATABASE MICRONS 1000 ; END UNITS MANUFACTURINGGRID 0.005 ; END LIBRARY".utf8)
        let document = try LEFLibraryReader.read(source)
        #expect(document.manufacturingGrid == 0.005)
        #expect(document.dbuPerMicron == 1000)
        let bytes = try LEFLibraryWriter.write(document)
        #expect(try LEFLibraryReader.read(bytes) == document)
        #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document)) == document)
    }

    @Test func technologyProjectionRetainsGrid() throws {
        let document = LEFDocument(manufacturingGrid: 0.005)
        let technology = try LEFTechIRConverter.toIRTechLibrary(document)
        #expect(technology.manufacturingGrid == 0.005)
        let decoded = try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(technology))
        #expect(decoded.manufacturingGrid == 0.005)
        #expect(LEFTechIRConverter.toLEFDocument(decoded).manufacturingGrid == 0.005)
        let legacy = try LEFTechIRConverter.toIRTechLibrary(LEFDocument())
        #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(legacy)).manufacturingGrid == nil)
    }

    @Test func legacySerializationKeepsAbsence() throws {
        let original = LEFDocument()
        let bytes = try JSONEncoder().encode(original)
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(object["manufacturingGrid"] == nil)
        #expect(try JSONDecoder().decode(LEFDocument.self, from: bytes).manufacturingGrid == nil)
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(original)).manufacturingGrid == nil)
    }

    @Test(arguments: ["0", "-0.005", "nan", "inf", "0.005 0.01", ""])
    func invalidSourceFails(_ value: String) {
        #expect(throws: LEFError.self) {
            try LEFLibraryReader.read(Data("VERSION 5.8 ; MANUFACTURINGGRID \(value) ; END LIBRARY".utf8))
        }
    }

    @Test(arguments: [0.0, -0.005, Double.nan, Double.infinity])
    func invalidValueCannotBeWritten(_ value: Double) {
        #expect(throws: LEFError.self) {
            try LEFLibraryWriter.write(LEFDocument(manufacturingGrid: value))
        }
        #expect(throws: LEFError.self) {
            try LEFTechIRConverter.toIRTechLibrary(LEFDocument(manufacturingGrid: value))
        }
    }

    @Test func repeatedAndNestedDeclarationsFail() {
        for body in [
            "MANUFACTURINGGRID 0.005 ; MANUFACTURINGGRID 0.01 ;",
            "LAYER m1 TYPE ROUTING ; MANUFACTURINGGRID 0.005 ; END m1"
        ] {
            #expect(throws: LEFError.self) {
                try LEFLibraryReader.read(Data("VERSION 5.8 ; \(body) END LIBRARY".utf8))
            }
        }
    }
}
