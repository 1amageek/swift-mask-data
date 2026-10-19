import Foundation
import Testing
import TechIR
@testable import LEF

@Suite("LEF unit precision declarations", .timeLimit(.minutes(1)))
struct LEFUnitTests {
    @Test func fullUnitBlockIsAccepted() throws {
        let source = """
        VERSION 5.8 ;
        UNITS
          TIME NANOSECONDS 1 ; CAPACITANCE PICOFARADS 1000 ; RESISTANCE OHMS 100 ;
          POWER MILLIWATTS 10000 ; CURRENT MILLIAMPS 10000 ; VOLTAGE VOLTS 1000 ;
          FREQUENCY MEGAHERTZ 1 ; DATABASE MICRONS 1000 ;
        END UNITS
        LAYER m1 TYPE ROUTING ; RESISTANCE RPERSQ 12.8 ; CAPACITANCE CPERSQDIST 0.02 ; END m1
        END LIBRARY
        """
        let document = try LEFLibraryReader.read(Data(source.utf8))
        #expect(document.dbuPerMicron == 1000)
        let expected = IRTechUnitDeclarations(timeNanoseconds: 1, capacitancePicofarads: 1000,
            resistanceOhms: 100, powerMilliwatts: 10000, currentMilliamps: 10000, voltageVolts: 1000, frequencyMegahertz: 1)
        #expect(document.unitDeclarations == expected)
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
        #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document)) == document)
        let technology = try LEFTechIRConverter.toIRTechLibrary(document)
        #expect(technology.unitDeclarations == expected)
        #expect(LEFTechIRConverter.toLEFDocument(technology).unitDeclarations == expected)
        #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(technology)).unitDeclarations == expected)
        #expect(document.layers.first?.resistance == 12.8)
        #expect(document.layers.first?.capacitance == 0.02)
    }

    @Test(arguments: ["", "UNITS END UNITS"])
    func omittedDatabaseUsesStandardPrecision(_ block: String) throws {
        let document = try LEFLibraryReader.read(Data("VERSION 5.8 ; \(block) END LIBRARY".utf8))
        #expect(document.dbuPerMicron == 100 && !document.hasDatabaseUnitsDeclaration)
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
        let technology = try LEFTechIRConverter.toIRTechLibrary(document)
        #expect(!technology.hasDatabaseUnitsDeclaration)
        #expect(LEFTechIRConverter.toLEFDocument(technology) == document)
    }
    @Test(arguments: [100, 200, 400, 800, 1000, 2000, 4000, 8000, 10000, 20000])
    func standardDatabaseFactors(_ factor: Int) throws {
        let document = try LEFLibraryReader.read(Data("VERSION 5.8 ; UNITS DATABASE MICRONS \(factor) ; END UNITS END LIBRARY".utf8))
        #expect(document.dbuPerMicron == Double(factor))
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
    }

    @Test(arguments: [0.0, -1, 300, 100.5, Double.nan, Double.infinity])
    func invalidDatabaseFactors(_ factor: Double) {
        #expect(throws: LEFError.self) { try LEFLibraryReader.read(Data("VERSION 5.8 ; UNITS DATABASE MICRONS \(factor) ; END UNITS END LIBRARY".utf8)) }
        #expect(throws: LEFError.self) { try LEFLibraryWriter.write(LEFDocument(dbuPerMicron: factor)) }
    }

    @Test(arguments: [
        "TIME SECONDS 1 ;", "CAPACITANCE FARADS 1 ;", "RESISTANCE KOHMS 1 ;", "POWER WATTS 1 ;",
        "CURRENT AMPS 1 ;", "VOLTAGE MVOLTS 1 ;", "FREQUENCY HERTZ 1 ;", "TIME NANOSECONDS ;",
        "TIME NANOSECONDS 1 2 ;", "TIME NANOSECONDS nan ;", "TIME NANOSECONDS 0 ;",
        "TIME NANOSECONDS -1 ;", "TIME NANOSECONDS 1 ; TIME NANOSECONDS 2 ;"
    ])
    func invalidUnitStatements(_ statement: String) {
        #expect(throws: LEFError.self) { try LEFLibraryReader.read(Data("VERSION 5.8 ; UNITS \(statement) END UNITS END LIBRARY".utf8)) }
    }

    @Test func invalidContextsAndOrder() {
        for body in [
            "TIME NANOSECONDS 1 ;",
            "LAYER m1 TYPE ROUTING ; TIME NANOSECONDS 1 ; END m1",
            "LAYER m1 TYPE ROUTING ; END m1 UNITS DATABASE MICRONS 1000 ; END UNITS",
            "UNITS END UNITS UNITS END UNITS"
        ] {
            #expect(throws: LEFError.self) { try LEFLibraryReader.read(Data("VERSION 5.8 ; \(body) END LIBRARY".utf8)) }
        }
    }

    @Test func programmaticInvalidUnitsFailAtBoundaries() {
        for units in [IRTechUnitDeclarations(timeNanoseconds: .nan), .init(capacitancePicofarads: 0),
                      .init(resistanceOhms: -1), .init(powerMilliwatts: .infinity), .init(currentMilliamps: 0),
                      .init(voltageVolts: -1), .init(frequencyMegahertz: .nan)] {
            let document = LEFDocument(unitDeclarations: units)
            #expect(throws: LEFError.self) { try LEFLibraryWriter.write(document) }
            #expect(throws: LEFError.self) { try LEFTechIRConverter.toIRTechLibrary(document) }
        }
    }

    @Test func legacySerializationPreservesStoredDistance() throws {
        let original = LEFDocument()
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "unitDeclarations")
        object.removeValue(forKey: "hasDatabaseUnitsDeclaration")
        let decoded = try JSONDecoder().decode(LEFDocument.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.unitDeclarations == .init() && decoded.dbuPerMicron == 1000 && decoded.hasDatabaseUnitsDeclaration)
        let technology = IRTechLibrary()
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(technology)) as? [String: Any])
        legacy.removeValue(forKey: "unitDeclarations")
        legacy.removeValue(forKey: "hasDatabaseUnitsDeclaration")
        #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONSerialization.data(withJSONObject: legacy)).unitDeclarations == .init())
        object.removeValue(forKey: "version")
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(LEFDocument.self, from: JSONSerialization.data(withJSONObject: object)) }
    }

    @Test func contradictoryImplicitDatabaseFails() {
        #expect(throws: LEFError.self) {
            try LEFLibraryWriter.write(LEFDocument(dbuPerMicron: 1000, hasDatabaseUnitsDeclaration: false))
        }
    }

}
