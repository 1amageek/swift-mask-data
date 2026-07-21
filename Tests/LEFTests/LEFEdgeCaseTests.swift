import CircuiteFoundation
import Testing
import Foundation
import LayoutIR
@testable import LEF

@Suite("LEF Tokenizer Edge Cases")
struct LEFTokenizerEdgeCaseTests {

    @Test func emptyInput() throws {
        #expect(try LEFTokenizer.tokenize("").isEmpty)
    }

    @Test func multipleConsecutiveComments() throws {
        let tokens = try LEFTokenizer.tokenize("# comment 1\n# comment 2\nVERSION 5.8 ;")
        #expect(tokens == ["VERSION", "5.8", ";"])
    }

    @Test func semicolonInQuotedString() throws {
        let tokens = try LEFTokenizer.tokenize("DIVIDERCHAR \";\" ;")
        #expect(tokens.contains("\";\""))
    }

    @Test func noTrailingNewline() throws {
        let tokens = try LEFTokenizer.tokenize("VERSION 5.8 ;")
        #expect(tokens == ["VERSION", "5.8", ";"])
    }

    @Test func unterminatedQuotedStringFails() {
        #expect(throws: LEFError.unterminatedQuotedString) {
            try LEFTokenizer.tokenize("DIVIDERCHAR \"")
        }
    }
}

@Suite("LEF Reader Edge Cases")
struct LEFReaderEdgeCaseTests {

    @Test func invalidEncoding() throws {
        let data = Data([0xFF, 0xFE, 0x00, 0x01])
        do {
            _ = try LEFLibraryReader.read(data)
            Issue.record("Should have thrown")
        } catch let error as LEFError {
            #expect(error == .invalidEncoding)
        }
    }

    @Test func emptyFile() throws {
        let doc = try LEFLibraryReader.read(Data("".utf8))
        #expect(doc.layers.isEmpty)
        #expect(doc.macros.isEmpty)
    }

    @Test func malformedNumberFailsClosed() {
        let lef = "VERSION 5.8 ; LAYER M1 TYPE ROUTING ; WIDTH wide ; END M1 END LIBRARY"
        #expect(throws: LEFError.invalidNumber(command: "WIDTH", value: "wide")) {
            try LEFLibraryReader.read(Data(lef.utf8))
        }
    }

    @Test func unterminatedLayerFailsClosed() {
        let lef = "VERSION 5.8 ; LAYER M1 TYPE ROUTING ; END LIBRARY"
        #expect(throws: LEFError.mismatchedEnd(expected: "M1", actual: "LIBRARY")) {
            try LEFLibraryReader.read(Data(lef.utf8))
        }
    }

    @Test func unsupportedCommandFailsClosed() {
        let lef = "VERSION 5.8 ; PROPERTYDEFINITIONS END PROPERTYDEFINITIONS END LIBRARY"
        #expect(throws: LEFError.unsupportedCommand("PROPERTYDEFINITIONS")) {
            try LEFLibraryReader.read(Data(lef.utf8))
        }
    }

    @Test func missingLibraryEndFailsClosed() {
        #expect(throws: LEFError.invalidStructure("END LIBRARY is missing")) {
            try LEFLibraryReader.read(Data("VERSION 5.8 ;".utf8))
        }
    }

    @Test func layerWithoutDirection() throws {
        let lef = """
        VERSION 5.8 ;
        LAYER via1
          TYPE CUT ;
        END via1
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        #expect(doc.layers[0].direction == nil)
        #expect(doc.layers[0].type == .cut)
    }

    @Test func layerWithAllTypes() throws {
        let lef = """
        VERSION 5.8 ;
        LAYER l1
          TYPE ROUTING ;
        END l1
        LAYER l2
          TYPE CUT ;
        END l2
        LAYER l3
          TYPE MASTERSLICE ;
        END l3
        LAYER l4
          TYPE OVERLAP ;
        END l4
        LAYER l5
          TYPE IMPLANT ;
        END l5
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        #expect(doc.layers.count == 5)
        #expect(doc.layers[0].type == .routing)
        #expect(doc.layers[1].type == .cut)
        #expect(doc.layers[2].type == .masterslice)
        #expect(doc.layers[3].type == .overlap)
        #expect(doc.layers[4].type == .implant)
    }

    @Test func macroWithOBS() throws {
        let lef = """
        VERSION 5.8 ;
        MACRO INV
          CLASS CORE ;
          SIZE 1.0 BY 2.0 ;
          OBS
            LAYER metal1 ;
              RECT 0.1 0.1 0.9 1.9 ;
          END
        END INV
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        #expect(doc.macros[0].obs.count == 1)
        #expect(doc.macros[0].obs[0].layerName == "metal1")
        #expect(doc.macros[0].obs[0].rects.count == 1)
    }

    @Test func viaWithMultipleRects() throws {
        let lef = """
        VERSION 5.8 ;
        VIA via1 ;
          LAYER metal1 ;
            RECT -0.1 -0.1 0.1 0.1 ;
            RECT -0.2 -0.2 0.2 0.2 ;
          LAYER via1 ;
            RECT -0.05 -0.05 0.05 0.05 ;
        END via1
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        #expect(doc.vias[0].layers.count == 2)
        #expect(doc.vias[0].layers[0].rects.count == 2)
        #expect(doc.vias[0].layers[1].rects.count == 1)
    }

    @Test func pinDirectionTypes() throws {
        let lef = """
        VERSION 5.8 ;
        MACRO INV
          PIN A
            DIRECTION INPUT ;
          END A
          PIN Y
            DIRECTION OUTPUT ;
          END Y
          PIN VDD
            DIRECTION INOUT ;
            USE POWER ;
          END VDD
        END INV
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        let pins = doc.macros[0].pins
        #expect(pins[0].direction == .input)
        #expect(pins[1].direction == .output)
        #expect(pins[2].direction == .inout_)
        #expect(pins[2].use == .power)
    }

    @Test func numericPrecisionInCoordinates() throws {
        let lef = """
        VERSION 5.8 ;
        LAYER metal1
          TYPE ROUTING ;
          PITCH 0.123 ;
          WIDTH 0.0456 ;
          SPACING 0.789 ;
        END metal1
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        let l = doc.layers[0]
        #expect(abs(l.pitch! - 0.123) < 1e-9)
        #expect(abs(l.width! - 0.0456) < 1e-9)
        #expect(abs(l.spacing! - 0.789) < 1e-9)
    }

    @Test func densityRulesRoundTripWithoutLoss() throws {
        let lef = """
        VERSION 5.8 ;
        LAYER metal1
          TYPE ROUTING ;
          MINIMUMDENSITY 27.5 ;
          MAXIMUMDENSITY 72.5 ;
          DENSITYCHECKWINDOW 10.25 20.5 ;
          DENSITYCHECKSTEP 5.125 ;
        END metal1
        END LIBRARY
        """

        let first = try LEFLibraryReader.read(Data(lef.utf8))
        let encoded = try LEFLibraryWriter.write(first)
        let second = try LEFLibraryReader.read(encoded)
        let layer = second.layers[0]

        #expect(layer.minimumDensity == 27.5)
        #expect(layer.maximumDensity == 72.5)
        #expect(layer.densityCheckWindow?.length == 10.25)
        #expect(layer.densityCheckWindow?.width == 20.5)
        #expect(layer.densityCheckStep == 5.125)
    }

    @Test func invalidDensityRangeFailsClosed() {
        let lef = "VERSION 5.8 ; LAYER M1 TYPE ROUTING ; MINIMUMDENSITY 101 ; END M1 END LIBRARY"
        #expect(throws: LEFError.invalidNumber(command: "MINIMUMDENSITY", value: "101")) {
            try LEFLibraryReader.read(Data(lef.utf8))
        }
    }

    @Test func inconsistentDensityRangeFailsClosed() {
        let lef = "VERSION 5.8 ; LAYER M1 TYPE ROUTING ; MINIMUMDENSITY 80 ; MAXIMUMDENSITY 20 ; END M1 END LIBRARY"
        #expect(throws: LEFError.invalidStructure("LAYER M1 minimum density exceeds maximum density")) {
            try LEFLibraryReader.read(Data(lef.utf8))
        }
    }
}

@Suite("LEF Writer Edge Cases")
struct LEFWriterEdgeCaseTests {

    @Test func writerPreservesAllLayerFields() throws {
        let doc = LEFDocument(
            layers: [LEFLayerDef(
                name: "m1", type: .routing, direction: .vertical,
                pitch: 0.28, width: 0.14, spacing: 0.14
            )]
        )
        let data = try LEFLibraryWriter.write(doc)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("DIRECTION VERTICAL"))
        #expect(text.contains("PITCH"))
        #expect(text.contains("WIDTH"))
        #expect(text.contains("SPACING"))
    }

    @Test func writerHandlesEmptyMacro() throws {
        let doc = LEFDocument(macros: [LEFMacroDef(name: "EMPTY")])
        let data = try LEFLibraryWriter.write(doc)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("MACRO EMPTY"))
        #expect(text.contains("END EMPTY"))
    }

    @Test func writerRejectsInconsistentDensityRange() {
        let document = LEFDocument(layers: [
            LEFLayerDef(
                name: "M1",
                type: .routing,
                minimumDensity: 80,
                maximumDensity: 20
            )
        ])

        #expect(throws: LEFError.invalidStructure(
            "LAYER M1 minimum density exceeds maximum density"
        )) {
            try LEFLibraryWriter.write(document)
        }
    }
}

@Suite("LEF IR Converter Edge Cases")
struct LEFIRConverterEdgeCaseTests {

    @Test func emptyDocument() throws {
        let doc = LEFDocument()
        let lib = try LEFIRConverter.toIRLibrary(doc)
        #expect(lib.cells.isEmpty)
    }

    @Test func unresolvedGeometryLayerFailsClosed() {
        let document = LEFDocument(macros: [
            LEFMacroDef(name: "CELL", obs: [
                LEFPort(layerName: "MISSING", rects: [LEFRect(x1: 0, y1: 0, x2: 1, y2: 1)])
            ])
        ])
        #expect(throws: LEFError.unresolvedLayer("MISSING")) {
            try LEFIRConverter.toIRLibrary(document)
        }
    }

    @Test func coordinateOverflowFailsClosed() throws {
        let document = LEFDocument(
            dbuPerMicron: 1000,
            layers: [LEFLayerDef(name: "M1", type: .routing)],
            macros: [LEFMacroDef(name: "CELL", obs: [
                LEFPort(
                    layerName: "M1",
                    rects: [LEFRect(x1: 0, y1: 0, x2: 3_000_000, y2: 1)]
                )
            ])]
        )

        do {
            _ = try LEFIRConverter.toIRLibrary(document)
            Issue.record("Expected coordinate overflow to fail")
        } catch let error as LEFError {
            guard case .coordinateOutOfRange(let context, _) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(context == "RECT maximum x")
        }
    }

    @Test func emptyBoundaryFailsClosed() throws {
        let library = IRLibrary(
            name: "TEST",
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1000),
            cells: [IRCell(name: "CELL", elements: [
                .boundary(IRBoundary(layer: 1, datatype: 0, points: [], properties: []))
            ])]
        )
        #expect(throws: LEFError.invalidGeometry("boundary has no points")) {
            try LEFIRConverter.toLEFDocument(library)
        }
    }

    @Test func emptySpacingTableEntryFailsClosed() {
        let document = LEFDocument(layers: [
            LEFLayerDef(
                name: "M1",
                type: .routing,
                spacingTable: LEFSpacingTable(
                    parallelRunLengths: [],
                    widthEntries: [.init(width: 0.1, spacings: [])]
                )
            )
        ])
        #expect(throws: LEFError.invalidGeometry("spacing-table width entry has no spacing value")) {
            try LEFTechIRConverter.toIRTechLibrary(document)
        }
    }

    @Test func macroWithMultiplePins() throws {
        let doc = LEFDocument(
            layers: [LEFLayerDef(name: "metal1", type: .routing)],
            macros: [LEFMacroDef(name: "NAND2", pins: [
                LEFPinDef(name: "A", ports: [LEFPort(layerName: "metal1", rects: [LEFRect(x1: 0, y1: 0, x2: 0.1, y2: 0.2)])]),
                LEFPinDef(name: "B", ports: [LEFPort(layerName: "metal1", rects: [LEFRect(x1: 0.3, y1: 0, x2: 0.4, y2: 0.2)])]),
                LEFPinDef(name: "Y", ports: [LEFPort(layerName: "metal1", rects: [LEFRect(x1: 0.6, y1: 0, x2: 0.7, y2: 0.2)])]),
            ])]
        )
        let lib = try LEFIRConverter.toIRLibrary(doc)
        let cell = lib.cells[0]
        // 3 pins × (1 boundary + 1 text) = 6 elements
        #expect(cell.elements.count == 6)
    }

    @Test func roundTripIRToLEFToIR() throws {
        let original = IRLibrary(
            name: "TEST",
            databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1000),
            cells: [IRCell(name: "BUF", elements: [
                .boundary(IRBoundary(layer: 1, datatype: 0, points: [
                    IRPoint(x: 0, y: 0), IRPoint(x: 500, y: 0),
                    IRPoint(x: 500, y: 1000), IRPoint(x: 0, y: 1000),
                    IRPoint(x: 0, y: 0),
                ], properties: []))
            ])]
        )
        let lef = try LEFIRConverter.toLEFDocument(original)
        let back = try LEFIRConverter.toIRLibrary(lef)
        // Cell name preserved
        #expect(back.cells[0].name == "BUF")
        // Geometry preserved (via OBS)
        #expect(!back.cells[0].elements.isEmpty)
    }
}
