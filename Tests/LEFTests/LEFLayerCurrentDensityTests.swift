import Foundation
import Testing
import LEF
import TechIR

@Suite("LEF scalar electrical current density", .timeLimit(.minutes(1)))
struct LEFLayerCurrentDensityTests {
    private func read(_ body: String, type: String = "ROUTING") throws -> LEFDocument {
        try LEFLibraryReader.read(Data("VERSION 5.8 ; LAYER L TYPE \(type) ;\n\(body)\nEND L END LIBRARY".utf8))
    }

    @Test(arguments: ["ROUTING", "CUT"])
    func allClassesAndUnitBearingRoundTrips(_ type: String) throws {
        let document = try read("""
        DCCURRENTDENSITY AVERAGE 0 ; ACCURRENTDENSITY PEAK 3.5 ;
        ACCURRENTDENSITY AVERAGE 2 ; ACCURRENTDENSITY RMS 1.25 ;
        """, type: type)
        let limits = document.layers[0].currentDensityLimits
        #expect(limits.map(\.kind) == [.dcAverage, .acPeak, .acAverage, .acRMS])
        #expect(limits.map { $0.quantity.value } == [0, 3.5, 2, 1.25])
        for limit in limits {
            if type == "CUT" {
                #expect(limit.quantity == .milliamperesPerSquareMicron(limit.quantity.value))
            } else {
                #expect(limit.quantity == .milliamperesPerMicron(limit.quantity.value))
            }
        }
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
        #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document)) == document)
        let library = try LEFTechIRConverter.toIRTechLibrary(document)
        #expect(library.layers[0].currentDensityLimits == limits)
        #expect(LEFTechIRConverter.toLEFDocument(library).layers[0].currentDensityLimits == limits)
        #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(library)) == library)
    }

    @Test func standardUnitsAreNotOverriddenByCommentsOrCurrentPrecision() throws {
        let document = try LEFLibraryReader.read(Data("""
        UNITS CURRENT MILLIAMPS 1000 ; END UNITS
        LAYER C TYPE CUT ;
        DCCURRENTDENSITY AVERAGE 0.36 ; # mA per via at 90 C
        END C
        LAYER M TYPE ROUTING ; DCCURRENTDENSITY AVERAGE 2.8 ; ACCURRENTDENSITY RMS 6.1 ; END M
        END LIBRARY
        """.utf8))
        #expect(document.layers[0].currentDensityLimits == [.init(kind: .dcAverage, quantity: .milliamperesPerSquareMicron(0.36))])
        #expect(document.layers[1].currentDensityLimits == [.init(kind: .dcAverage, quantity: .milliamperesPerMicron(2.8)),
                                                         .init(kind: .acRMS, quantity: .milliamperesPerMicron(6.1))])
        #expect(try LEFTechIRConverter.toIRTechLibrary(document).layers[0].currentDensityLimits == document.layers[0].currentDensityLimits)
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
    }

    @Test(arguments: ["DCCURRENTDENSITY PEAK 1 ;", "DCCURRENTDENSITY RMS 1 ;", "ACCURRENTDENSITY DC 1 ;",
        "DCCURRENTDENSITY AVERAGE ;", "ACCURRENTDENSITY RMS 1 2 ;", "DCCURRENTDENSITY AVERAGE -1 ;",
        "ACCURRENTDENSITY RMS nan ;", "ACCURRENTDENSITY PEAK inf ;", "ACCURRENTDENSITY RMS 1",
        "DCCURRENTDENSITY AVERAGE 1 ; DCCURRENTDENSITY AVERAGE 2 ;",
        "ACCURRENTDENSITY RMS 1 ; ACCURRENTDENSITY RMS 2 ;"])
    func invalidSource(_ body: String) {
        #expect(throws: LEFError.self) { _ = try read(body) }
    }

    @Test(arguments: [("ACCURRENTDENSITY", "RMS", "FREQUENCY"), ("ACCURRENTDENSITY", "PEAK", "WIDTH"),
        ("ACCURRENTDENSITY", "AVERAGE", "CUTAREA"), ("DCCURRENTDENSITY", "AVERAGE", "CUTAREA"),
        ("DCCURRENTDENSITY", "AVERAGE", "WIDTH"), ("DCCURRENTDENSITY", "AVERAGE", "TABLEENTRIES")])
    func tablesAreExplicitlyRefused(_ command: String, _ classification: String, _ axis: String) {
        #expect(throws: LEFError.unsupportedCommand("\(command) \(axis) table")) {
            _ = try read("\(command) \(classification) \(axis) 1 2 ; TABLEENTRIES 3 4 ;")
        }
    }

    @Test(arguments: ["MASTERSLICE", "OVERLAP", "IMPLANT"])
    func unsupportedContexts(_ type: String) {
        #expect(throws: LEFError.self) { _ = try read("DCCURRENTDENSITY AVERAGE 1 ;", type: type) }
        #expect(throws: LEFError.self) { _ = try read("ACCURRENTDENSITY RMS 1 ;", type: type) }
        #expect(throws: LEFError.self) {
            _ = try LEFLibraryReader.read(Data("DCCURRENTDENSITY AVERAGE 1 ; END LIBRARY".utf8))
        }
    }

    @Test func writerAndForwardProjectionValidateKindsUnitsAndValues() throws {
        let source = try read("")
        let cases: [[IRTechCurrentDensityLimit]] = [
            [.init(kind: .dcAverage, quantity: .milliamperesPerSquareMicron(1))],
            [.init(kind: .acPeak, quantity: .milliamperesPerMicron(-1))],
            [.init(kind: .acRMS, quantity: .milliamperesPerMicron(.nan))],
            [.init(kind: .dcAverage, quantity: .milliamperesPerMicron(1)), .init(kind: .dcAverage, quantity: .milliamperesPerMicron(2))]]
        for limits in cases {
            var document = source; document.layers[0].currentDensityLimits = limits
            #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(document) }
            #expect(throws: LEFError.self) { _ = try LEFTechIRConverter.toIRTechLibrary(document) }
        }
        var library = try LEFTechIRConverter.toIRTechLibrary(source)
        library.layers[0].currentDensityLimits = cases[0]
        let document = LEFTechIRConverter.toLEFDocument(library)
        #expect(document.layers[0].currentDensityLimits == cases[0])
        #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(document) }
    }

    @Test func legacyMissingCurrentLimitsStayAbsent() throws {
        let document = try read("")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(document.layers[0])) as? [String: Any])
        json.removeValue(forKey: "currentDensityLimits")
        #expect(try JSONDecoder().decode(LEFLayerDef.self, from: JSONSerialization.data(withJSONObject: json)).currentDensityLimits.isEmpty)
        let library = try LEFTechIRConverter.toIRTechLibrary(document)
        json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(library.layers[0])) as? [String: Any])
        json.removeValue(forKey: "currentDensityLimits")
        #expect(try JSONDecoder().decode(IRTechLayerDef.self, from: JSONSerialization.data(withJSONObject: json)).currentDensityLimits.isEmpty)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LEF_REAL_TECHLEF_DIRECTORY"] != nil))
    func unchangedActualPrefixAndExactMetalFragmentsWithFullNextRefusal() throws {
        let directory = try #require(ProcessInfo.processInfo.environment["LEF_REAL_TECHLEF_DIRECTORY"])
        for corner in ["nom", "min", "max"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("sky130_fd_sc_hd__\(corner).tlef")
            let data = try Data(contentsOf: url)
            let source = try #require(String(data: data, encoding: .utf8))
            let end = try #require(source.range(of: "END mcon"))
            let prefix = Data((source[..<end.upperBound] + "\nEND LIBRARY\n").utf8)
            let document = try LEFLibraryReader.read(prefix)
            let cut = try #require(document.layers.first(where: { $0.name == "mcon" }))
            let metalStart = try #require(source.range(of: "LAYER met1"))
            let metalEnd = try #require(source.range(of: "END met1", range: metalStart.upperBound..<source.endIndex))
            let metalBlock = source[metalStart.lowerBound..<metalEnd.lowerBound]
            let scalarLines = metalBlock.split(separator: "\n", omittingEmptySubsequences: false).filter {
                let line = $0.trimmingCharacters(in: .whitespaces)
                return line.hasPrefix("DCCURRENTDENSITY") || line.hasPrefix("ACCURRENTDENSITY")
            }
            #expect(scalarLines.count == 2)
            // Exact statement fragments test electrical facts; this is not full met1 intake.
            let fragmentSource = "LAYER met1 TYPE ROUTING ;\n" + scalarLines.joined(separator: "\n") + "\nEND met1 END LIBRARY"
            let fragment = try LEFLibraryReader.read(Data(fragmentSource.utf8))
            let metal = try #require(fragment.layers.first)
            #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(fragment)) == fragment)
            #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(fragment)) == fragment)
            let fragmentLibrary = try LEFTechIRConverter.toIRTechLibrary(fragment)
            #expect(fragmentLibrary.layers[0].currentDensityLimits == metal.currentDensityLimits)
            #expect(LEFTechIRConverter.toLEFDocument(fragmentLibrary).layers[0].currentDensityLimits == metal.currentDensityLimits)
            #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(fragmentLibrary)) == fragmentLibrary)
            #expect(cut.currentDensityLimits == [.init(kind: .dcAverage, quantity: .milliamperesPerSquareMicron(0.36))])
            #expect(metal.currentDensityLimits == [.init(kind: .dcAverage, quantity: .milliamperesPerMicron(2.8)),
                                                 .init(kind: .acRMS, quantity: .milliamperesPerMicron(6.1))])
            #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
            #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document)) == document)
            let library = try LEFTechIRConverter.toIRTechLibrary(document)
            #expect(library.layers.map(\.currentDensityLimits) == document.layers.map(\.currentDensityLimits))
            #expect(LEFTechIRConverter.toLEFDocument(library).layers.map(\.currentDensityLimits) == document.layers.map(\.currentDensityLimits))
            #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(library)) == library)
            #expect(try LEFLibraryReader.read(data).viaGenerationRules.count == 25)
        }
    }
}
