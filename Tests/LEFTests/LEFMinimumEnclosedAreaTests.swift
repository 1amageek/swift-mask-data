import Foundation
import Testing
import LEF
import TechIR

@Suite("LEF minimum enclosed hole area", .timeLimit(.minutes(1)))
struct LEFMinimumEnclosedAreaTests {
    private func read(_ body: String, type: String = "ROUTING") throws -> LEFDocument {
        try LEFLibraryReader.read(Data("LAYER L TYPE \(type) ; \(body) END L END LIBRARY".utf8))
    }

    @Test(arguments: [0.0, 0.14, 1.234567891])
    func holeAreaIsDistinctAndNotPrecisionRescaled(_ area: Double) throws {
        let document = try LEFLibraryReader.read(Data("""
        UNITS DATABASE MICRONS 1000 ; END UNITS
        LAYER L TYPE ROUTING ; AREA 0.083 ; MINENCLOSEDAREA \(area) ; END L END LIBRARY
        """.utf8))
        #expect(document.layers[0].area == 0.083)
        #expect(document.layers[0].minimumEnclosedAreas == [area])
        #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
        #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document)) == document)
        let library = try LEFTechIRConverter.toIRTechLibrary(document)
        #expect(library.designRules[0].minArea == 0.083)
        #expect(library.designRules[0].minEnclosedArea == area)
        #expect(library.layers[0].minArea == 0.083)
        #expect(LEFTechIRConverter.toLEFDocument(library).layers[0].minimumEnclosedAreas == [area])
        #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(library)) == library)
        let holeOnly = try LEFTechIRConverter.toIRTechLibrary(read("MINENCLOSEDAREA \(area) ;"))
        #expect(holeOnly.designRules.count == 1)
        #expect(holeOnly.designRules[0].minArea == nil)
        #expect(holeOnly.designRules[0].minEnclosedArea == area)
    }

    @Test func absenceAndLegacyJSONRemainAbsent() throws {
        let document = try read("")
        #expect(document.layers[0].minimumEnclosedAreas.isEmpty)
        #expect(try LEFTechIRConverter.toIRTechLibrary(document).designRules.isEmpty)
        let legacy = Data(#"{"name":"L","type":"ROUTING"}"#.utf8)
        #expect(try JSONDecoder().decode(LEFLayerDef.self, from: legacy).minimumEnclosedAreas.isEmpty)
        let rule = try JSONDecoder().decode(IRTechDesignRule.self, from: Data(#"{"layerName":"L"}"#.utf8))
        #expect(rule.minEnclosedArea == nil)
    }

    @Test(arguments: ["MINENCLOSEDAREA ;", "MINENCLOSEDAREA 1 2 ;", "MINENCLOSEDAREA -1 ;",
        "MINENCLOSEDAREA nan ;", "MINENCLOSEDAREA inf ;", "MINENCLOSEDAREA 1",
        "MINENCLOSEDAREA 1 ; MINENCLOSEDAREA 1 ;", "MINENCLOSEDAREA 1 ; MINENCLOSEDAREA 2 ;"])
    func invalidSource(_ body: String) {
        #expect(throws: LEFError.self) { _ = try read(body) }
    }

    @Test(arguments: ["MINENCLOSEDAREA 0.4 WIDTH 0.15 ;",
        "MINENCLOSEDAREA 0.3 ; MINENCLOSEDAREA 0.4 WIDTH 0.15 ;",
        "MINENCLOSEDAREA 0.4 WIDTH 0 ;", "MINENCLOSEDAREA 0.4 WIDTH ;"])
    func widthConditionCannotBecomeUnconditional(_ body: String) {
        #expect(throws: LEFError.unsupportedCommand("MINENCLOSEDAREA WIDTH")) { _ = try read(body) }
    }

    @Test(arguments: ["CUT", "MASTERSLICE", "OVERLAP", "IMPLANT"])
    func routingContextOnly(_ type: String) {
        #expect(throws: LEFError.self) { _ = try read("MINENCLOSEDAREA 0.14 ;", type: type) }
        #expect(throws: LEFError.self) {
            _ = try LEFLibraryReader.read(Data("MINENCLOSEDAREA 0.14 ; END LIBRARY".utf8))
        }
    }

    @Test func rawInvalidFactsRefuseWriterAndProjection() throws {
        for areas in [[-1.0], [Double.nan], [Double.infinity], [1.0, 1.0], [1.0, 2.0]] {
            var document = try read(""); document.layers[0].minimumEnclosedAreas = areas
            #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(document) }
            #expect(throws: LEFError.self) { _ = try LEFTechIRConverter.toIRTechLibrary(document) }
        }
        let invalidJSON = Data(#"{"name":"L","type":"CUT","minimumEnclosedAreas":[0.14]}"#.utf8)
        let layer = try JSONDecoder().decode(LEFLayerDef.self, from: invalidJSON)
        #expect(layer.minimumEnclosedAreas == [0.14])
        let document = LEFDocument(layers: [layer])
        #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(document) }
        #expect(throws: LEFError.self) { _ = try LEFTechIRConverter.toIRTechLibrary(document) }
    }

    @Test func reverseKeepsAllDuplicateAndInvalidFactsForRefusal() throws {
        for areas in [[0.14, 0.14], [0.14, 0.3], [-1.0], [Double.infinity]] {
            var library = try LEFTechIRConverter.toIRTechLibrary(read(""))
            library.designRules = areas.map { IRTechDesignRule(layerName: "L", minEnclosedArea: $0) }
            let document = LEFTechIRConverter.toLEFDocument(library)
            #expect(document.layers[0].minimumEnclosedAreas == areas)
            #expect(document.layers[0].area == nil)
            #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(document) }
        }
        var library = try LEFTechIRConverter.toIRTechLibrary(read("", type: "CUT"))
        library.designRules = [.init(layerName: "L", minEnclosedArea: 0.14)]
        #expect(throws: LEFError.self) { _ = try LEFLibraryWriter.write(LEFTechIRConverter.toLEFDocument(library)) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LEF_REAL_TECHLEF_DIRECTORY"] != nil))
    func unchangedOriginalLayersRoundTripAndFullSourceFacts() throws {
        let directory = try #require(ProcessInfo.processInfo.environment["LEF_REAL_TECHLEF_DIRECTORY"])
        for corner in ["nom", "min", "max"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: directory).appendingPathComponent("sky130_fd_sc_hd__\(corner).tlef"))
            let source = try #require(String(data: data, encoding: .utf8))
            let end = try #require(source.range(of: "END met5"))
            let prefix = Data((source[..<end.upperBound] + "\nEND LIBRARY\n").utf8)
            let document = try LEFLibraryReader.read(prefix)
            for name in ["met1", "met2"] {
                let layer = try #require(document.layers.first { $0.name == name })
                #expect(layer.minimumEnclosedAreas == [0.14])
                #expect(layer.area != 0.14)
            }
            #expect(document.layers.filter { !$0.minimumEnclosedAreas.isEmpty }.map(\.name) == ["met1", "met2"])
            #expect(try LEFLibraryReader.read(LEFLibraryWriter.write(document)) == document)
            #expect(try JSONDecoder().decode(LEFDocument.self, from: JSONEncoder().encode(document)) == document)
            let library = try LEFTechIRConverter.toIRTechLibrary(document)
            #expect(library.designRules.filter { $0.minEnclosedArea != nil }.map(\.layerName) == ["met1", "met2"])
            #expect(library.designRules.compactMap(\.minEnclosedArea) == [0.14, 0.14])
            #expect(LEFTechIRConverter.toLEFDocument(library).layers.map(\.minimumEnclosedAreas) == document.layers.map(\.minimumEnclosedAreas))
            #expect(try JSONDecoder().decode(IRTechLibrary.self, from: JSONEncoder().encode(library)) == library)
            #expect(try LEFLibraryReader.read(data).viaGenerationRules.count == 25)
        }
    }
}
