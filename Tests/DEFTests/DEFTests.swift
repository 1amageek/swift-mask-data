import Testing
import Foundation
import LayoutIR
@testable import DEF

// MARK: - DEF Tokenizer Tests

@Suite("DEFTokenizer")
struct DEFTokenizerTests {

    @Test func basicTokens() {
        let tokens = DEFTokenizer.tokenize("VERSION 5.8 ;")
        #expect(tokens == ["VERSION", "5.8", ";"])
    }

    @Test func parentheses() {
        let tokens = DEFTokenizer.tokenize("DIEAREA ( 0 0 ) ( 1000 1000 ) ;")
        #expect(tokens.contains("("))
        #expect(tokens.contains(")"))
    }
}

// MARK: - DEF Document Tests

@Suite("DEFDocument")
struct DEFDocumentTests {

    @Test func construction() {
        let doc = DEFDocument(designName: "test", dbuPerMicron: 1000)
        #expect(doc.designName == "test")
        #expect(doc.dbuPerMicron == 1000)
    }
}

// MARK: - DEF Orientation Tests

@Suite("DEFOrientation")
struct DEFOrientationTests {

    @Test func allOrientationsMapped() {
        for orient in DEFOrientation.allCases {
            let t = DEFIRConverter.orientationToTransform(orient)
            let back = DEFIRConverter.transformToOrientation(t)
            #expect(back == orient)
        }
    }
}

// MARK: - DEF Reader Tests

@Suite("DEFLibraryReader")
struct DEFLibraryReaderTests {

    @Test func headerParsing() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN mydesign ;
        UNITS DISTANCE MICRONS 2000 ;
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.version == "5.8")
        #expect(doc.designName == "mydesign")
        #expect(doc.dbuPerMicron == 2000)
    }

    @Test func dieArea() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        DIEAREA ( 0 0 ) ( 10000 20000 ) ;
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        let bb = doc.dieArea?.boundingBox
        #expect(bb?.x1 == 0)
        #expect(bb?.y1 == 0)
        #expect(bb?.x2 == 10000)
        #expect(bb?.y2 == 20000)
    }

    @Test func singleComponent() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        COMPONENTS 1 ;
          - u1 INV + PLACED ( 100 200 ) N ;
        END COMPONENTS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.components.count == 1)
        #expect(doc.components[0].name == "u1")
        #expect(doc.components[0].macro == "INV")
        #expect(doc.components[0].x == 100)
        #expect(doc.components[0].y == 200)
        #expect(doc.components[0].orientation == .n)
    }

    @Test func componentWithOrientation() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        COMPONENTS 2 ;
          - u1 INV + PLACED ( 0 0 ) FN ;
          - u2 BUF + PLACED ( 100 0 ) S ;
        END COMPONENTS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.components.count == 2)
        #expect(doc.components[0].orientation == .fn)
        #expect(doc.components[1].orientation == .s)
    }

    @Test func pins() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        PINS 1 ;
          - clk + NET clk + DIRECTION INPUT + PLACED ( 0 500 ) N ;
        END PINS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.pins.count == 1)
        #expect(doc.pins[0].name == "clk")
        #expect(doc.pins[0].netName == "clk")
        #expect(doc.pins[0].direction == .input)
        #expect(doc.pins[0].x == 0)
        #expect(doc.pins[0].y == 500)
    }

    @Test func nets() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        NETS 1 ;
          - net1 ( u1 A ) ( u2 Y ) ;
        END NETS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.nets.count == 1)
        #expect(doc.nets[0].name == "net1")
        #expect(doc.nets[0].connections.count == 2)
        #expect(doc.nets[0].connections[0].componentName == "u1")
        #expect(doc.nets[0].connections[0].pinName == "A")
    }

    @Test func specialNets() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        SPECIALNETS 1 ;
          - VDD + USE POWER + ROUTED metal1 200 ( 0 0 ) ( 1000 0 ) ;
        END SPECIALNETS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.specialNets.count == 1)
        #expect(doc.specialNets[0].name == "VDD")
        #expect(doc.specialNets[0].use == DEFSpecialNet.NetUse.power)
        #expect(doc.specialNets[0].routing.count == 1)
        #expect(doc.specialNets[0].routing[0].layerName == "metal1")
        #expect(doc.specialNets[0].routing[0].width == 200)
        #expect(doc.specialNets[0].routing[0].points.count == 2)
    }
}

// MARK: - DEF Writer Tests

@Suite("DEFLibraryWriter")
struct DEFLibraryWriterTests {

    @Test func writeMinimalDesign() throws {
        let doc = DEFDocument(designName: "test", dbuPerMicron: 1000)
        let data = try DEFLibraryWriter.write(doc)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("VERSION 5.8"))
        #expect(text.contains("DESIGN test"))
        #expect(text.contains("END DESIGN"))
    }
}

// MARK: - DEF Round-Trip Tests

@Suite("DEF Round-Trip")
struct DEFRoundTripTests {

    @Test func roundTrip() throws {
        let original = DEFDocument(
            designName: "chip",
            dbuPerMicron: 1000,
            dieArea: DEFDieArea(x1: 0, y1: 0, x2: 10000, y2: 20000),
            components: [
                DEFComponent(name: "u1", macro: "INV", x: 100, y: 200, orientation: .n),
            ]
        )
        let data = try DEFLibraryWriter.write(original)
        let result = try DEFLibraryReader.read(data)

        #expect(result.designName == "chip")
        #expect(result.dbuPerMicron == 1000)
        let bb = result.dieArea?.boundingBox
        #expect(bb?.x1 == 0)
        #expect(bb?.x2 == 10000)
        #expect(result.components.count == 1)
        #expect(result.components[0].name == "u1")
    }
}

// MARK: - DEF IR Converter Tests

@Suite("DEFIRConverter")
struct DEFIRConverterTests {

    @Test func defToIR() {
        let doc = DEFDocument(
            designName: "chip",
            dbuPerMicron: 1000,
            dieArea: DEFDieArea(x1: 0, y1: 0, x2: 10000, y2: 20000),
            components: [
                DEFComponent(name: "u1", macro: "INV", x: 100, y: 200, orientation: .fn),
            ],
            pins: [
                DEFPin(name: "clk", x: 0, y: 500),
            ]
        )
        let lib = DEFIRConverter.toIRLibrary(doc)
        #expect(lib.cells.count == 1)
        #expect(lib.cells[0].name == "chip")
        // dieArea boundary + 1 cellRef + 1 text (pin)
        #expect(lib.cells[0].elements.count == 3)
    }
}
