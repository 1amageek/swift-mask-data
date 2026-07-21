import CircuiteFoundation
import Foundation
import Testing
import LayoutIR
import GDSII
import OASIS
import LEF
import DEF
import CIF
import DXF
import FormatDetector

@Suite("Golden Mask Data Corpus")
struct GoldenMaskDataCorpusTests {
    @Test func independentGDSIIFixtureHasExpectedSemantics() throws {
        let data = try Self.fixtureData(named: "minimal.gds")
        #expect(FormatDetector.detect(data) == .gdsii)
        let library = try GDSLibraryReader.read(data)
        #expect(library.name == "FIXTURE")
        #expect(library.databaseUnitScale.databaseUnitsPerMicrometer == 1000)
        #expect(library.cells.isEmpty)
    }

    @Test func independentOASISFixtureHasExpectedSemantics() throws {
        let data = try Self.fixtureData(named: "minimal.oas")
        #expect(FormatDetector.detect(data) == .oasis)
        let library = try OASISLibraryReader.read(data)
        #expect(library.name == "FIXTURE")
        #expect(library.databaseUnitScale.databaseUnitsPerMicrometer == 1000)
        #expect(library.cells.isEmpty)
    }

    @Test func independentLEFFixtureHasExpectedSemantics() throws {
        let document = try LEFLibraryReader.read(Self.fixtureData(named: "minimal.lef"))
        #expect(document.dbuPerMicron == 1000)
        #expect(document.layers.map(\.name) == ["M1"])
        #expect(document.layers[0].width == 0.1)
    }

    @Test func independentDEFFixtureHasExpectedSemantics() throws {
        let document = try DEFLibraryReader.read(Self.fixtureData(named: "minimal.def"))
        #expect(document.designName == "FIXTURE")
        #expect(document.dbuPerMicron == 1000)
        #expect(document.dieArea != nil)
    }

    @Test func independentCIFFixtureHasExpectedSemantics() throws {
        let library = try CIFLibraryReader.read(
            Self.fixtureData(named: "minimal.cif"),
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1000)
        )
        #expect(library.cells.count == 1)
        #expect(library.cells[0].elements.count == 1)
        guard case .boundary(let boundary) = library.cells[0].elements[0] else {
            Issue.record("Expected CIF box boundary")
            return
        }
        #expect(boundary.layer == 1)
    }

    @Test func independentDXFFixtureHasExpectedSemantics() throws {
        let library = try DXFLibraryReader.read(
            Self.fixtureData(named: "minimal.dxf"),
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1000)
        )
        #expect(library.cells.count == 1)
        guard case .path(let path) = library.cells[0].elements[0] else {
            Issue.record("Expected DXF line path")
            return
        }
        #expect(path.points == [IRPoint(x: 0, y: 0), IRPoint(x: 1000, y: 2000)])
    }

    @Test func gdsiiGoldenCorpusRoundTripIsStable() throws {
        let original = try Self.goldenLayoutLibrary()
        let data = try GDSLibraryWriter.write(original)

        #expect(FormatDetector.detect(data) == .gdsii)

        let loaded = try GDSLibraryReader.read(data)
        Self.expectGoldenLayout(loaded)

        let rewritten = try GDSLibraryWriter.write(loaded)
        #expect(FormatDetector.detect(rewritten) == .gdsii)
        let reloaded = try GDSLibraryReader.read(rewritten)
        Self.expectGoldenLayout(reloaded)
    }

    @Test func oasisGoldenCorpusRoundTripIsStable() throws {
        let original = try Self.goldenLayoutLibrary()
        let data = try OASISLibraryWriter.write(original)

        #expect(FormatDetector.detect(data) == .oasis)

        let loaded = try OASISLibraryReader.read(data)
        Self.expectGoldenLayout(loaded)

        let rewritten = try OASISLibraryWriter.write(loaded)
        let reloaded = try OASISLibraryReader.read(rewritten)
        Self.expectGoldenLayout(reloaded)
    }

    @Test func lefGoldenTechnologyCorpusRoundTripIsStable() throws {
        let data = Data(Self.goldenLEF.utf8)

        #expect(FormatDetector.detect(data) == .lef)

        let loaded = try LEFLibraryReader.read(data)
        #expect(loaded.version == "5.8")
        #expect(loaded.dbuPerMicron == 1000)
        #expect(loaded.layers.map(\.name) == ["ACTIVE", "POLY", "M1", "VIA1", "M2"])

        let rewritten = try LEFLibraryWriter.write(loaded)
        let reloaded = try LEFLibraryReader.read(rewritten)
        #expect(reloaded.layers.map(\.name) == loaded.layers.map(\.name))
        #expect(reloaded.layers.map(\.type) == loaded.layers.map(\.type))
    }

    @Test func defGoldenDesignCorpusRoundTripIsStable() throws {
        let data = Data(Self.goldenDEF.utf8)

        #expect(FormatDetector.detect(data) == .def)

        let loaded = try DEFLibraryReader.read(data)
        #expect(loaded.designName == "voltage_divider")
        #expect(loaded.dbuPerMicron == 1000)
        #expect(loaded.pins.map(\.name) == ["vin", "out", "vss"])
        #expect(loaded.nets.map(\.name) == ["vin", "out", "0"])

        let rewritten = try DEFLibraryWriter.write(loaded)
        let reloaded = try DEFLibraryReader.read(rewritten)
        #expect(reloaded.pins.map(\.name) == loaded.pins.map(\.name))
        #expect(reloaded.nets.map(\.name) == loaded.nets.map(\.name))
    }

    private static func goldenLayoutLibrary() throws -> IRLibrary {
        let top = IRCell(name: "TOP", elements: [
            .boundary(IRBoundary(
                layer: 1,
                datatype: 0,
                points: [
                    IRPoint(x: 0, y: 0),
                    IRPoint(x: 2400, y: 0),
                    IRPoint(x: 2400, y: 1200),
                    IRPoint(x: 0, y: 1200),
                    IRPoint(x: 0, y: 0),
                ],
                properties: []
            )),
            .path(IRPath(
                layer: 3,
                datatype: 0,
                pathType: .halfWidthExtend,
                width: 120,
                points: [
                    IRPoint(x: 0, y: 600),
                    IRPoint(x: 1200, y: 600),
                    IRPoint(x: 2400, y: 600),
                ],
                properties: []
            )),
            .text(IRText(
                layer: 3,
                texttype: 0,
                transform: .identity,
                position: IRPoint(x: 0, y: 600),
                string: "vin",
                properties: []
            )),
            .text(IRText(
                layer: 3,
                texttype: 0,
                transform: .identity,
                position: IRPoint(x: 1200, y: 600),
                string: "out",
                properties: []
            )),
            .text(IRText(
                layer: 3,
                texttype: 0,
                transform: .identity,
                position: IRPoint(x: 2400, y: 600),
                string: "0",
                properties: []
            )),
        ])

        return IRLibrary(
            name: "GOLDEN_VDIV",
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1000),
            cells: [top]
        )
    }

    private static func expectGoldenLayout(_ library: IRLibrary) {
        #expect(library.name == "GOLDEN_VDIV")
        #expect(library.cells.map(\.name) == ["TOP"])
        let elements = library.cells[0].elements
        #expect(elements.count == 5)
        #expect(elements.filter { element in
            if case .boundary = element { return true }
            return false
        }.count == 1)
        #expect(elements.filter { element in
            if case .path = element { return true }
            return false
        }.count == 1)
        let labels = elements.compactMap { element -> String? in
            if case .text(let text) = element { return text.string }
            return nil
        }
        #expect(labels == ["vin", "out", "0"])
    }

    private static func fixtureData(named name: String) throws -> Data {
        let fixturesDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        return try Data(contentsOf: fixturesDirectory.appendingPathComponent(name))
    }


    private static let goldenLEF = """
    VERSION 5.8 ;
    BUSBITCHARS "[]" ;
    DIVIDERCHAR "/" ;
    UNITS
      DATABASE MICRONS 1000 ;
    END UNITS
    LAYER ACTIVE
      TYPE MASTERSLICE ;
    END ACTIVE
    LAYER POLY
      TYPE ROUTING ;
      DIRECTION HORIZONTAL ;
      WIDTH 0.05 ;
      SPACING 0.05 ;
    END POLY
    LAYER M1
      TYPE ROUTING ;
      DIRECTION HORIZONTAL ;
      WIDTH 0.08 ;
      SPACING 0.08 ;
    END M1
    LAYER VIA1
      TYPE CUT ;
      WIDTH 0.06 ;
      SPACING 0.06 ;
    END VIA1
    LAYER M2
      TYPE ROUTING ;
      DIRECTION VERTICAL ;
      WIDTH 0.08 ;
      SPACING 0.08 ;
    END M2
    END LIBRARY
    """

    private static let goldenDEF = """
    VERSION 5.8 ;
    DIVIDERCHAR "/" ;
    BUSBITCHARS "[]" ;
    DESIGN voltage_divider ;
    UNITS DISTANCE MICRONS 1000 ;
    DIEAREA ( 0 0 ) ( 2400 1200 ) ;
    PINS 3 ;
      - vin + NET vin + DIRECTION INPUT + USE SIGNAL + PLACED ( 0 600 ) N ;
      - out + NET out + DIRECTION OUTPUT + USE SIGNAL + PLACED ( 1200 600 ) N ;
      - vss + NET 0 + DIRECTION INOUT + USE GROUND + PLACED ( 2400 600 ) N ;
    END PINS
    NETS 3 ;
      - vin ( PIN vin ) ;
      - out ( PIN out ) ;
      - 0 ( PIN vss ) ;
    END NETS
    END DESIGN
    """
}
