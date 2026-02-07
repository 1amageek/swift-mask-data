import Testing
import Foundation
import LayoutIR
@testable import DEF

@Suite("DEF Tokenizer Edge Cases")
struct DEFTokenizerEdgeCaseTests {

    @Test func emptyInput() {
        #expect(DEFTokenizer.tokenize("").isEmpty)
    }

    @Test func commentSkipping() {
        let tokens = DEFTokenizer.tokenize("# comment\nVERSION 5.8 ;")
        #expect(tokens == ["VERSION", "5.8", ";"])
    }

    @Test func extraWhitespaceInParentheses() {
        let tokens = DEFTokenizer.tokenize("(   100   200   )")
        #expect(tokens.contains("100"))
        #expect(tokens.contains("200"))
    }
}

@Suite("DEF Reader Edge Cases")
struct DEFReaderEdgeCaseTests {

    @Test func invalidEncoding() throws {
        let data = Data([0xFF, 0xFE, 0x00, 0x01])
        do {
            _ = try DEFLibraryReader.read(data)
            Issue.record("Should have thrown")
        } catch let error as DEFError {
            #expect(error == .invalidEncoding)
        }
    }

    @Test func emptyFile() throws {
        let doc = try DEFLibraryReader.read(Data("".utf8))
        #expect(doc.components.isEmpty)
        #expect(doc.designName.isEmpty)
    }

    @Test func negativeCoordinates() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        DIEAREA ( -1000 -2000 ) ( 5000 6000 ) ;
        COMPONENTS 1 ;
          - u1 INV + PLACED ( -500 -300 ) N ;
        END COMPONENTS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        let bb = doc.dieArea?.boundingBox
        #expect(bb?.x1 == -1000)
        #expect(bb?.y1 == -2000)
        #expect(doc.components[0].x == -500)
        #expect(doc.components[0].y == -300)
    }

    @Test func fixedVsPlacedComponent() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        COMPONENTS 2 ;
          - u1 INV + PLACED ( 0 0 ) N ;
          - u2 BUF + FIXED ( 100 200 ) FN ;
        END COMPONENTS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.components.count == 2)
        #expect(doc.components[0].placementStatus == DEFComponent.PlacementStatus.placed)
        #expect(doc.components[1].placementStatus == DEFComponent.PlacementStatus.fixed)
        #expect(doc.components[1].x == 100)
        #expect(doc.components[1].y == 200)
        #expect(doc.components[1].orientation == .fn)
    }

    @Test func allOrientations() throws {
        let orients = ["N", "S", "E", "W", "FN", "FS", "FE", "FW"]
        for (i, orient) in orients.enumerated() {
            let def = """
            VERSION 5.8 ;
            DESIGN test ;
            COMPONENTS 1 ;
              - u\(i) INV + PLACED ( 0 0 ) \(orient) ;
            END COMPONENTS
            END DESIGN
            """
            let doc = try DEFLibraryReader.read(Data(def.utf8))
            #expect(doc.components[0].orientation.rawValue == orient)
        }
    }

    @Test func multipleNetsWithConnections() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        NETS 3 ;
          - n1 ( u1 A ) ( u2 B ) ;
          - n2 ( u3 Y ) ;
          - clk ( PIN clk ) ( u1 CK ) ( u2 CK ) ( u3 CK ) ;
        END NETS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.nets.count == 3)
        #expect(doc.nets[0].connections.count == 2)
        #expect(doc.nets[1].connections.count == 1)
        #expect(doc.nets[2].connections.count == 4)
        #expect(doc.nets[2].name == "clk")
    }

    @Test func specialNetWithMultipleSegments() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        SPECIALNETS 1 ;
          - VDD + USE POWER + ROUTED metal1 200 ( 0 0 ) ( 1000 0 ) + ROUTED metal2 300 ( 0 0 ) ( 0 1000 ) ;
        END SPECIALNETS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.specialNets[0].routing.count == 2)
        #expect(doc.specialNets[0].routing[0].layerName == "metal1")
        #expect(doc.specialNets[0].routing[0].width == 200)
        #expect(doc.specialNets[0].routing[1].layerName == "metal2")
        #expect(doc.specialNets[0].routing[1].width == 300)
    }

    @Test func pinWithAllProperties() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        PINS 1 ;
          - data + NET data + DIRECTION OUTPUT + LAYER metal1 + PLACED ( 500 600 ) S ;
        END PINS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        let pin = doc.pins[0]
        #expect(pin.name == "data")
        #expect(pin.netName == "data")
        #expect(pin.direction == DEFPin.Direction.output)
        #expect(pin.layerName == "metal1")
        #expect(pin.x == 500)
        #expect(pin.y == 600)
        #expect(pin.orientation == .s)
    }
}

@Suite("DEF Writer Edge Cases")
struct DEFWriterEdgeCaseTests {

    @Test func writeAllSections() throws {
        let doc = DEFDocument(
            designName: "chip",
            dbuPerMicron: 2000,
            dieArea: DEFDieArea(x1: 0, y1: 0, x2: 10000, y2: 20000),
            components: [DEFComponent(name: "u1", macro: "INV", x: 100, y: 200, orientation: .fn)],
            pins: [DEFPin(name: "clk", direction: .input, netName: "clk", x: 0, y: 500)],
            nets: [DEFNet(name: "n1", connections: [DEFConnection(componentName: "u1", pinName: "A")])],
            specialNets: [DEFSpecialNet(name: "VDD", use: .power)]
        )
        let data = try DEFLibraryWriter.write(doc)
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("DESIGN chip"))
        #expect(text.contains("MICRONS 2000"))
        #expect(text.contains("DIEAREA"))
        #expect(text.contains("COMPONENTS 1"))
        #expect(text.contains("PINS 1"))
        #expect(text.contains("NETS 1"))
        #expect(text.contains("SPECIALNETS 1"))
        #expect(text.contains("END DESIGN"))
    }
}

@Suite("DEF Round-Trip Fidelity")
struct DEFRoundTripFidelityTests {

    @Test func fullRoundTrip() throws {
        let original = DEFDocument(
            designName: "testchip",
            dbuPerMicron: 1000,
            dieArea: DEFDieArea(x1: 0, y1: 0, x2: 50000, y2: 30000),
            components: [
                DEFComponent(name: "u1", macro: "INV", x: 1000, y: 2000, orientation: .n, placementStatus: .placed),
                DEFComponent(name: "u2", macro: "BUF", x: 5000, y: 2000, orientation: .fs, placementStatus: .placed),
            ],
            pins: [
                DEFPin(name: "clk", direction: .input, netName: "clk", x: 0, y: 1000, orientation: .n, placementStatus: .placed),
            ],
            nets: [
                DEFNet(name: "net1", connections: [
                    DEFConnection(componentName: "u1", pinName: "Y"),
                    DEFConnection(componentName: "u2", pinName: "A"),
                ]),
            ]
        )
        let data = try DEFLibraryWriter.write(original)
        let result = try DEFLibraryReader.read(data)

        #expect(result.designName == original.designName)
        #expect(result.dbuPerMicron == original.dbuPerMicron)
        let bb = result.dieArea?.boundingBox
        #expect(bb?.x1 == 0)
        #expect(bb?.x2 == 50000)
        #expect(result.components.count == 2)
        #expect(result.components[0].orientation == .n)
        #expect(result.components[1].orientation == .fs)
        #expect(result.pins.count == 1)
        #expect(result.nets.count == 1)
        #expect(result.nets[0].connections.count == 2)
    }
}

@Suite("DEF IR Converter Edge Cases")
struct DEFIRConverterEdgeCaseTests {

    @Test func emptyDesign() {
        let doc = DEFDocument(designName: "empty")
        let lib = DEFIRConverter.toIRLibrary(doc)
        #expect(lib.cells.count == 1)
        #expect(lib.cells[0].elements.isEmpty)
    }

    @Test func orientationRoundTrip() {
        for orient in DEFOrientation.allCases {
            let t = DEFIRConverter.orientationToTransform(orient)
            let back = DEFIRConverter.transformToOrientation(t)
            #expect(back == orient, "Failed for orientation \(orient.rawValue)")
        }
    }

    @Test func convertDEFToIRPreservesCoordinates() {
        let doc = DEFDocument(
            designName: "test",
            dieArea: DEFDieArea(x1: -100, y1: -200, x2: 5000, y2: 6000),
            components: [
                DEFComponent(name: "u1", macro: "INV", x: 1000, y: 2000, orientation: .s),
            ]
        )
        let lib = DEFIRConverter.toIRLibrary(doc)
        let cell = lib.cells[0]

        // First element is dieArea boundary
        if case .boundary(let b) = cell.elements[0] {
            let xs = b.points.map(\.x)
            let ys = b.points.map(\.y)
            #expect(xs.min() == -100)
            #expect(ys.min() == -200)
            #expect(xs.max() == 5000)
            #expect(ys.max() == 6000)
        } else {
            Issue.record("Expected dieArea boundary")
        }

        // Second element is cellRef
        if case .cellRef(let ref) = cell.elements[1] {
            #expect(ref.origin == IRPoint(x: 1000, y: 2000))
            #expect(ref.transform.angle == 180.0)
        } else {
            Issue.record("Expected cellRef")
        }
    }
}
