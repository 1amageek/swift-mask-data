import Testing
import Foundation
import LayoutIR
@testable import LEF

// MARK: - LEF Tokenizer Tests

@Suite("LEFTokenizer")
struct LEFTokenizerTests {

    @Test func basicTokens() {
        let tokens = LEFTokenizer.tokenize("VERSION 5.8 ;")
        #expect(tokens == ["VERSION", "5.8", ";"])
    }

    @Test func quotedString() {
        let tokens = LEFTokenizer.tokenize("DIVIDERCHAR \"/\" ;")
        #expect(tokens.contains("\"/\""))
    }

    @Test func numericValues() {
        let tokens = LEFTokenizer.tokenize("PITCH 0.28 ;")
        #expect(tokens == ["PITCH", "0.28", ";"])
    }

    @Test func commentSkipping() {
        let tokens = LEFTokenizer.tokenize("# this is a comment\nVERSION 5.8 ;")
        #expect(tokens == ["VERSION", "5.8", ";"])
    }
}

// MARK: - LEF Document Tests

@Suite("LEFDocument")
struct LEFDocumentTests {

    @Test func construction() {
        let doc = LEFDocument(
            version: "5.8",
            dbuPerMicron: 1000,
            layers: [LEFLayerDef(name: "metal1", type: .routing, direction: .horizontal)],
            macros: []
        )
        #expect(doc.version == "5.8")
        #expect(doc.dbuPerMicron == 1000)
        #expect(doc.layers.count == 1)
    }
}

// MARK: - LEF Reader Tests

@Suite("LEFLibraryReader")
struct LEFLibraryReaderTests {

    @Test func versionAndUnits() throws {
        let lef = """
        VERSION 5.8 ;
        UNITS
          DATABASE MICRONS 2000 ;
        END UNITS
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        #expect(doc.version == "5.8")
        #expect(doc.dbuPerMicron == 2000)
    }

    @Test func singleLayer() throws {
        let lef = """
        VERSION 5.8 ;
        LAYER metal1
          TYPE ROUTING ;
          DIRECTION HORIZONTAL ;
          PITCH 0.28 ;
          WIDTH 0.14 ;
          SPACING 0.14 ;
        END metal1
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        #expect(doc.layers.count == 1)
        let layer = doc.layers[0]
        #expect(layer.name == "metal1")
        #expect(layer.type == .routing)
        #expect(layer.direction == .horizontal)
        #expect(layer.pitch == 0.28)
        #expect(layer.width == 0.14)
        #expect(layer.spacing == 0.14)
    }

    @Test func multipleLayersAndVia() throws {
        let lef = """
        VERSION 5.8 ;
        LAYER metal1
          TYPE ROUTING ;
        END metal1
        LAYER via1
          TYPE CUT ;
        END via1
        LAYER metal2
          TYPE ROUTING ;
        END metal2
        VIA via1_def ;
          LAYER metal1 ;
            RECT -0.07 -0.07 0.07 0.07 ;
          LAYER via1 ;
            RECT -0.07 -0.07 0.07 0.07 ;
          LAYER metal2 ;
            RECT -0.07 -0.07 0.07 0.07 ;
        END via1_def
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        #expect(doc.layers.count == 3)
        #expect(doc.vias.count == 1)
        #expect(doc.vias[0].name == "via1_def")
        #expect(doc.vias[0].layers.count == 3)
    }

    @Test func macroSizeOnly() throws {
        let lef = """
        VERSION 5.8 ;
        MACRO INV
          CLASS CORE ;
          SIZE 1.4 BY 2.8 ;
          SYMMETRY X Y ;
        END INV
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        #expect(doc.macros.count == 1)
        let m = doc.macros[0]
        #expect(m.name == "INV")
        #expect(m.macroClass == .core)
        #expect(m.width == 1.4)
        #expect(m.height == 2.8)
        #expect(m.symmetry == [.x, .y])
    }

    @Test func macroWithPin() throws {
        let lef = """
        VERSION 5.8 ;
        LAYER metal1
          TYPE ROUTING ;
        END metal1
        MACRO INV
          CLASS CORE ;
          SIZE 1.4 BY 2.8 ;
          PIN A
            DIRECTION INPUT ;
            USE SIGNAL ;
            PORT
              LAYER metal1 ;
                RECT 0.0 0.0 0.14 0.28 ;
            END
          END A
          PIN Y
            DIRECTION OUTPUT ;
            PORT
              LAYER metal1 ;
                RECT 1.0 0.0 1.4 0.28 ;
            END
          END Y
        END INV
        END LIBRARY
        """
        let doc = try LEFLibraryReader.read(Data(lef.utf8))
        let m = doc.macros[0]
        #expect(m.pins.count == 2)
        #expect(m.pins[0].name == "A")
        #expect(m.pins[0].direction == .input)
        #expect(m.pins[0].use == .signal)
        #expect(m.pins[0].ports.count == 1)
        #expect(m.pins[0].ports[0].layerName == "metal1")
        #expect(m.pins[0].ports[0].rects.count == 1)
        #expect(m.pins[1].name == "Y")
        #expect(m.pins[1].direction == .output)
    }
}

// MARK: - LEF Writer Tests

@Suite("LEFLibraryWriter")
struct LEFLibraryWriterTests {

    @Test func writeMinimalDocument() throws {
        let doc = LEFDocument(version: "5.8", dbuPerMicron: 1000)
        let data = try LEFLibraryWriter.write(doc)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("VERSION 5.8"))
        #expect(text.contains("DATABASE MICRONS 1000"))
        #expect(text.contains("END LIBRARY"))
    }

    @Test func writeMacro() throws {
        let doc = LEFDocument(
            version: "5.8",
            dbuPerMicron: 1000,
            macros: [LEFMacroDef(name: "BUF", macroClass: .core, width: 2.0, height: 3.0)]
        )
        let data = try LEFLibraryWriter.write(doc)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("MACRO BUF"))
        #expect(text.contains("CLASS CORE"))
        #expect(text.contains("SIZE 2 BY 3"))
        #expect(text.contains("END BUF"))
    }
}

// MARK: - LEF Round-Trip Tests

@Suite("LEF Round-Trip")
struct LEFRoundTripTests {

    @Test func roundTrip() throws {
        let original = LEFDocument(
            version: "5.8",
            dbuPerMicron: 1000,
            layers: [
                LEFLayerDef(name: "metal1", type: .routing, direction: .horizontal, pitch: 0.28, width: 0.14),
            ],
            macros: [
                LEFMacroDef(name: "INV", macroClass: .core, width: 1.4, height: 2.8),
            ]
        )
        let data = try LEFLibraryWriter.write(original)
        let result = try LEFLibraryReader.read(data)

        #expect(result.version == original.version)
        #expect(result.dbuPerMicron == original.dbuPerMicron)
        #expect(result.layers.count == original.layers.count)
        #expect(result.layers[0].name == "metal1")
        #expect(result.macros.count == 1)
        #expect(result.macros[0].name == "INV")
        #expect(result.macros[0].width == 1.4)
    }
}

// MARK: - LEF IR Converter Tests

@Suite("LEFIRConverter")
struct LEFIRConverterTests {

    @Test func lefToIR() {
        let doc = LEFDocument(
            version: "5.8",
            dbuPerMicron: 1000,
            layers: [
                LEFLayerDef(name: "metal1", type: .routing),
            ],
            macros: [
                LEFMacroDef(name: "INV", pins: [
                    LEFPinDef(name: "A", ports: [
                        LEFPort(layerName: "metal1", rects: [LEFRect(x1: 0, y1: 0, x2: 0.14, y2: 0.28)])
                    ])
                ])
            ]
        )
        let lib = LEFIRConverter.toIRLibrary(doc)
        #expect(lib.cells.count == 1)
        #expect(lib.cells[0].name == "INV")
        // 1 boundary + 1 text label for pin A
        #expect(lib.cells[0].elements.count == 2)
    }

    @Test func irToLEF() {
        let lib = IRLibrary(
            name: "TEST",
            units: IRUnits(dbuPerMicron: 1000),
            cells: [
                IRCell(name: "BUF", elements: [
                    .boundary(IRBoundary(layer: 1, datatype: 0, points: [
                        IRPoint(x: 0, y: 0), IRPoint(x: 1000, y: 0),
                        IRPoint(x: 1000, y: 2000), IRPoint(x: 0, y: 2000),
                        IRPoint(x: 0, y: 0),
                    ], properties: []))
                ])
            ]
        )
        let doc = LEFIRConverter.toLEFDocument(lib)
        #expect(doc.macros.count == 1)
        #expect(doc.macros[0].name == "BUF")
        #expect(doc.macros[0].obs.count == 1)
        let rect = doc.macros[0].obs[0].rects[0]
        #expect(rect.x1 == 0)
        #expect(rect.y1 == 0)
        #expect(rect.x2 == 1.0)
        #expect(rect.y2 == 2.0)
    }
}
