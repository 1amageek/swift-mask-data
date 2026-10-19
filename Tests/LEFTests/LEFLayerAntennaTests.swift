import Foundation
import Testing
import LEF
import TechIR

@Suite("LEF layer antenna", .timeLimit(.minutes(1)))
struct LEFLayerAntennaTests {
    private func read(_ body: String, type: String = "ROUTING") throws -> LEFDocument {
        try LEFLibraryReader.read(Data("VERSION 5.8 ; LAYER L TYPE \(type) ; \(body) END L END LIBRARY".utf8))
    }

    @Test func scopedSequenceAndAllRoundTrips() throws {
        let document = try read("""
        ANTENNADIFFAREARATIO 2.5 ;
        ANTENNAMODEL OXIDE2 ; ANTENNADIFFAREARATIO PWL ((0 40)(0.125 20)(2 20)) ;
        ANTENNADIFFAREARATIO 30 ; ANTENNAMODEL OXIDE1 ;
        ANTENNADIFFSIDEAREARATIO PWL ( (0 75) (0.0125 75) (0.0225 85.125) (22.5 10200) ) ;
        ANTENNAMODEL OXIDE3 ; ANTENNADIFFAREARATIO 10 ;
        ANTENNAMODEL OXIDE4 ; ANTENNADIFFSIDEAREARATIO 12 ;
        """)
        let statements = document.layers[0].antennaStatements
        #expect(statements.count == 10)
        #expect(statements[0] == .ratio(kind: .diffusionArea, value: .scalar(2.5)))
        #expect(statements[1] == .model(.oxide2))
        #expect(statements[2] == .ratio(kind: .diffusionArea, value: .piecewiseLinear([
            .init(diffusionAreaSquareMicrons: 0, ratio: 40),
            .init(diffusionAreaSquareMicrons: 0.125, ratio: 20),
            .init(diffusionAreaSquareMicrons: 2, ratio: 20)])))
        #expect(statements[3] == .ratio(kind: .diffusionArea, value: .scalar(30)))
        #expect(statements[4] == .model(.oxide1))
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
        #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document)) == document)
        let library = try LEFTechIRConverter.toIRTechLibrary(document)
        #expect(library.layers[0].antennaStatements == statements)
        #expect(library.antennaRules.isEmpty)
        #expect(LEFTechIRConverter.toLEFDocument(library).layers == document.layers)
        #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(library)) == library)
    }

    @Test func scopeIsLocalAndAbsentModelIsRetained() throws {
        let document = try LEFLibraryReader.read(Data("""
        LAYER A TYPE CUT ; ANTENNAMODEL OXIDE4 ; ANTENNADIFFAREARATIO 6 ; END A
        LAYER B TYPE CUT ; ANTENNADIFFAREARATIO PWL ((0 3)(0.125 4.5)) ; END B
        END LIBRARY
        """.utf8))
        #expect(document.layers[0].antennaStatements.first == .model(.oxide4))
        #expect(document.layers[1].antennaStatements.count == 1)
        #expect(document.layers[1].antennaStatements.first == .ratio(kind: .diffusionArea, value: .piecewiseLinear([
            .init(diffusionAreaSquareMicrons: 0, ratio: 3), .init(diffusionAreaSquareMicrons: 0.125, ratio: 4.5)])))
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)).layers == document.layers)
    }

    @Test(arguments: ["ANTENNAMODEL OXIDE5 ;", "ANTENNAMODEL ;", "ANTENNAMODEL OXIDE1 extra ;",
        "ANTENNADIFFAREARATIO ;", "ANTENNADIFFAREARATIO -1 ;", "ANTENNADIFFAREARATIO nan ;",
        "ANTENNADIFFAREARATIO inf ;", "ANTENNADIFFAREARATIO 1e30 ;", "ANTENNADIFFAREARATIO 1 2 ;",
        "ANTENNADIFFAREARATIO PWL () ;", "ANTENNADIFFAREARATIO PWL ((0 1)) ;",
        "ANTENNADIFFAREARATIO PWL ((0 1)(0 2)) ;", "ANTENNADIFFAREARATIO PWL ((1 1)(0 2)) ;",
        "ANTENNADIFFAREARATIO PWL ((-1 1)(0 2)) ;", "ANTENNADIFFAREARATIO PWL ((0 -1)(1 2)) ;",
        "ANTENNADIFFAREARATIO PWL ((0 1)(nan 2)) ;", "ANTENNADIFFAREARATIO PWL ((0 1)(1 inf)) ;",
        "ANTENNADIFFAREARATIO PWL ((0 1)(1 2) ;", "ANTENNADIFFAREARATIO PWL ((0 1)(1 2))) ;",
        "ANTENNADIFFAREARATIO PWL ((0 1)(1 2)) extra ;", "ANTENNADIFFAREARATIO PWL ((0)(1 2)) ;",
        "ANTENNADIFFAREARATIO 1"])
    func malformedSource(_ body: String) {
        #expect(throws: LEFError.self) { _ = try read(body) }
    }

    @Test(arguments: ["MASTERSLICE", "IMPLANT", "OVERLAP"])
    func unsupportedLayerType(_ type: String) {
        #expect(throws: LEFError.self) { _ = try read("ANTENNAMODEL OXIDE1 ;", type: type) }
        #expect(throws: LEFError.self) { _ = try read("ANTENNADIFFAREARATIO 1 ;", type: type) }
    }

    @Test func sidewallRequiresRoutingAndOtherLawsRemainUnsupported() {
        #expect(throws: LEFError.self) { _ = try read("ANTENNADIFFSIDEAREARATIO 1 ;", type: "CUT") }
        for command in ["ANTENNAAREARATIO", "ANTENNASIDEAREARATIO", "ANTENNACUMDIFFAREARATIO", "ANTENNAAREAFACTOR"] {
            #expect(throws: LEFError.unsupportedCommand(command)) { _ = try read("\(command) 1 ;") }
        }
        #expect(throws: LEFError.self) { _ = try LEFLibraryReader.read(Data("ANTENNAMODEL OXIDE1 ; END LIBRARY".utf8)) }
    }

    @Test func invalidOwnedValuesFailWriterAndProjection() throws {
        let source = try read("")
        let invalid: [IRTechAntennaStatement] = [
            .ratio(kind: .diffusionArea, value: .scalar(.nan)),
            .ratio(kind: .diffusionArea, value: .scalar(-1)),
            .ratio(kind: .diffusionArea, value: .piecewiseLinear([])),
            .ratio(kind: .diffusionArea, value: .piecewiseLinear([
                .init(diffusionAreaSquareMicrons: 1, ratio: 1), .init(diffusionAreaSquareMicrons: 0, ratio: 2)]))]
        for statement in invalid {
            var document = source; document.layers[0].antennaStatements = [statement]
            #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(document) }
            #expect(throws: LEFError.self) { _ = try LEFTechIRConverter.toIRTechLibrary(document) }
        }
        var library = try LEFTechIRConverter.toIRTechLibrary(source)
        library.layers[0].type = .cut
        library.layers[0].antennaStatements = [.ratio(kind: .diffusionSideArea, value: .scalar(1))]
        let document = LEFTechIRConverter.toLEFDocument(library)
        #expect(document.layers[0].antennaStatements == library.layers[0].antennaStatements)
        #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(document) }
    }

    @Test func legacyLayerAbsenceAndLegacyRatioRemainCompatible() throws {
        let document = try read("")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(document.layers[0])) as? [String: Any])
        json.removeValue(forKey: "antennaStatements")
        #expect(try JSONDecoder().decode(LEFLayerDef.self, from: JSONSerialization.data(withJSONObject: json)).antennaStatements.isEmpty)
        let library = try LEFTechIRConverter.toIRTechLibrary(document)
        json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(library.layers[0])) as? [String: Any])
        json.removeValue(forKey: "antennaStatements")
        #expect(try JSONDecoder().decode(IRTechLayerDef.self, from: JSONSerialization.data(withJSONObject: json)).antennaStatements.isEmpty)
        let legacy = IRTechAntennaRule(layerName: "L", maxRatio: 400)
        #expect(try JSONDecoder().decode(IRTechAntennaRule.self, from: JSONEncoder().encode(legacy)) == legacy)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LEF_REAL_TECHLEF_DIRECTORY"] != nil))
    func unchangedActualSourcePrefixAndFullSourceFacts() throws {
        let directory = try #require(ProcessInfo.processInfo.environment["LEF_REAL_TECHLEF_DIRECTORY"])
        for corner in ["nom", "min", "max"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("sky130_fd_sc_hd__\(corner).tlef")
            let data = try Data(contentsOf: url)
            let source = try #require(String(data: data, encoding: .utf8))
            let end = try #require(source.range(of: "END li1"))
            let prefix = Data((source[..<end.upperBound] + "\nEND LIBRARY\n").utf8)
            let document = try LEFLibraryReader.read(prefix)
            let layer = try #require(document.layers.first(where: { $0.name == "li1" }))
            #expect(layer.antennaStatements == [.model(.oxide1), .ratio(kind: .diffusionSideArea, value: .piecewiseLinear([
                .init(diffusionAreaSquareMicrons: 0, ratio: 75), .init(diffusionAreaSquareMicrons: 0.0125, ratio: 75),
                .init(diffusionAreaSquareMicrons: 0.0225, ratio: 85.125), .init(diffusionAreaSquareMicrons: 22.5, ratio: 10200)]))])
            #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
            #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document)) == document)
            let library = try LEFTechIRConverter.toIRTechLibrary(document)
            #expect(library.layers.first(where: { $0.name == "li1" })?.antennaStatements == layer.antennaStatements)
            #expect(LEFTechIRConverter.toLEFDocument(library).layers.first(where: { $0.name == "li1" })?.antennaStatements == layer.antennaStatements)
            #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(library)) == library)
            #expect(try LEFLibraryReader.read(data).viaGenerationRules.count == 25)
        }
    }
}
