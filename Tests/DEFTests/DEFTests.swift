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

    @Test func invalidDieAreaCoordinateThrowsInsteadOfFallingBackToZero() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        DIEAREA ( 0 not-a-number ) ( 1000 1000 ) ;
        END DESIGN
        """

        #expect(throws: DEFError.invalidNumber(context: "DIEAREA y", token: "not-a-number")) {
            _ = try DEFLibraryReader.read(Data(def.utf8))
        }
    }

    @Test func invalidComponentPlacementThrowsInsteadOfFallingBackToZero() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        COMPONENTS 1 ;
          - u1 INV + PLACED ( bad 200 ) N ;
        END COMPONENTS
        END DESIGN
        """

        #expect(throws: DEFError.invalidNumber(context: "COMPONENT u1 placement x", token: "bad")) {
            _ = try DEFLibraryReader.read(Data(def.utf8))
        }
    }

    @Test func routeWildcardWithoutPreviousPointThrows() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        NETS 1 ;
          - sig + ROUTED met1 ( * 100 ) ;
        END NETS
        END DESIGN
        """

        #expect(throws: DEFError.missingNumber(context: "NET sig route wildcard")) {
            _ = try DEFLibraryReader.read(Data(def.utf8))
        }
    }

    @Test func invalidSpecialNetWidthThrowsInsteadOfZeroWidthRoute() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        SPECIALNETS 1 ;
          - VDD + ROUTED metal1 bad ( 0 0 ) ( 1000 0 ) ;
        END SPECIALNETS
        END DESIGN
        """

        #expect(throws: DEFError.invalidNumber(context: "SPECIALNET VDD route width", token: "bad")) {
            _ = try DEFLibraryReader.read(Data(def.utf8))
        }
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

    @Test func defToIR() throws {
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
        let lib = try DEFIRConverter.toIRLibrary(doc)
        #expect(lib.cells.count == 2)
        #expect(lib.cells[0].name == "chip")
        #expect(lib.cells[1].name == "INV")
        // dieArea boundary + 1 cellRef + 1 text (pin)
        #expect(lib.cells[0].elements.count == 3)
    }

    @Test func componentProvenanceSurvivesIRRoundTrip() throws {
        let original = DEFDocument(
            designName: "chip",
            dbuPerMicron: 1000,
            dieArea: DEFDieArea(x1: 0, y1: 0, x2: 10000, y2: 20000),
            components: [
                DEFComponent(
                    name: "u1",
                    macro: "INV",
                    x: 100,
                    y: 200,
                    orientation: .fn,
                    placementStatus: .fixed
                ),
            ],
            pins: [
                DEFPin(
                    name: "clk",
                    netName: "clk",
                    x: 0,
                    y: 500,
                    placementStatus: .placed
                ),
            ]
        )
        let library = try DEFIRConverter.toIRLibrary(original)
        let decoded = DEFIRConverter.toDEFDocument(library)

        #expect(decoded.designName == "chip")
        #expect(decoded.dieArea?.boundingBox?.x2 == 10000)
        #expect(decoded.components.count == 1)
        #expect(decoded.components[0].name == "u1")
        #expect(decoded.components[0].macro == "INV")
        #expect(decoded.components[0].x == 100)
        #expect(decoded.components[0].y == 200)
        #expect(decoded.components[0].orientation == .fn)
        #expect(decoded.components[0].placementStatus == .fixed)
        #expect(decoded.pins.count == 1)
        #expect(decoded.pins[0].name == "clk")
        #expect(decoded.pins[0].netName == "clk")
        #expect(decoded.pins[0].placementStatus == .placed)
    }

    @Test func irCellRefsExportAsPlacedDEFComponents() {
        let reference = IRCellRef(
            cellName: "INV",
            origin: IRPoint(x: 320, y: 640),
            transform: DEFIRConverter.orientationToTransform(.s)
        )
        let library = IRLibrary(
            name: "chip",
            units: IRUnits(dbuPerMicron: 1000),
            cells: [
                IRCell(name: "chip", elements: [.cellRef(reference)]),
                IRCell(name: "INV"),
            ]
        )

        let document = DEFIRConverter.toDEFDocument(library)

        #expect(document.components.count == 1)
        #expect(document.components[0].name == "INV")
        #expect(document.components[0].macro == "INV")
        #expect(document.components[0].x == 320)
        #expect(document.components[0].y == 640)
        #expect(document.components[0].orientation == .s)
        #expect(document.components[0].placementStatus == .placed)
    }

    @Test func netRoutingSurvivesIRRoundTrip() throws {
        let original = DEFDocument(
            designName: "chip",
            dbuPerMicron: 1000,
            pins: [
                DEFPin(name: "clk", netName: "clk", x: 100, y: 200, placementStatus: .placed),
            ],
            nets: [
                DEFNet(
                    name: "clk",
                    connections: [
                        DEFConnection(componentName: "PIN", pinName: "clk"),
                        DEFConnection(componentName: "u1", pinName: "A"),
                    ],
                    use: .clock,
                    routing: [
                        DEFRouteWire(
                            status: .routed,
                            layerName: "metal1",
                            points: [
                                IRPoint(x: 100, y: 200),
                                IRPoint(x: 500, y: 200),
                            ],
                            viaName: "VIA1"
                        ),
                    ]
                ),
            ],
            specialNets: [
                DEFSpecialNet(
                    name: "VDD",
                    connections: [
                        DEFConnection(componentName: "*", pinName: "VDD"),
                    ],
                    use: .power,
                    routing: [
                        DEFRouteSegment(
                            status: .fixed,
                            layerName: "metal2",
                            width: 300,
                            points: [
                                DEFRoutePoint(x: 0, y: 1000, ext: 50),
                                DEFRoutePoint(x: 1000, y: nil),
                                DEFRoutePoint(viaName: "VIA2"),
                            ],
                            shape: .stripe
                        ),
                    ],
                    source: "NETLIST",
                    weight: 5
                ),
            ]
        )

        let library = try DEFIRConverter.toIRLibraryChecked(
            original,
            layerNumbers: try DEFLayerNumberMapping(layerNumbersByName: [
                "metal1": 1,
                "metal2": 2,
            ])
        )
        let routedPaths = library.cells[0].elements.compactMap { element -> IRPath? in
            if case .path(let path) = element { return path }
            return nil
        }
        #expect(routedPaths.count == 2)

        let decoded = DEFIRConverter.toDEFDocument(library)

        #expect(decoded.pins.count == 1)
        #expect(decoded.pins[0].name == "clk")
        #expect(decoded.pins[0].netName == "clk")
        #expect(decoded.nets.count == 1)
        #expect(decoded.nets[0].name == "clk")
        #expect(decoded.nets[0].connections.count == 2)
        #expect(decoded.nets[0].use == .clock)
        #expect(decoded.nets[0].routing.count == 1)
        #expect(decoded.nets[0].routing[0].layerName == "metal1")
        #expect(decoded.nets[0].routing[0].viaName == "VIA1")
        #expect(decoded.specialNets.count == 1)
        #expect(decoded.specialNets[0].name == "VDD")
        #expect(decoded.specialNets[0].use == .power)
        #expect(decoded.specialNets[0].source == "NETLIST")
        #expect(decoded.specialNets[0].weight == 5)
        #expect(decoded.specialNets[0].routing.count == 1)
        #expect(decoded.specialNets[0].routing[0].status == .fixed)
        #expect(decoded.specialNets[0].routing[0].layerName == "metal2")
        #expect(decoded.specialNets[0].routing[0].width == 300)
        #expect(decoded.specialNets[0].routing[0].shape == .stripe)
        #expect(decoded.specialNets[0].routing[0].points.count == 3)
        #expect(decoded.specialNets[0].routing[0].points[1].y == nil)
        #expect(decoded.specialNets[0].routing[0].points[2].viaName == "VIA2")
    }

    @Test func defLayerNamesDoNotAliasByDigitExtraction() throws {
        let original = DEFDocument(
            designName: "chip",
            dbuPerMicron: 1000,
            nets: [
                DEFNet(
                    name: "local",
                    routing: [
                        DEFRouteWire(
                            layerName: "li1",
                            points: [
                                IRPoint(x: 0, y: 0),
                                IRPoint(x: 100, y: 0),
                            ]
                        ),
                    ]
                ),
                DEFNet(
                    name: "metal",
                    routing: [
                        DEFRouteWire(
                            layerName: "met1",
                            points: [
                                IRPoint(x: 0, y: 100),
                                IRPoint(x: 100, y: 100),
                            ]
                        ),
                    ]
                ),
            ]
        )

        let library = try DEFIRConverter.toIRLibraryChecked(
            original,
            layerNumbers: try DEFLayerNumberMapping(layerNumbersByName: [
                "li1": 10,
                "met1": 1,
            ])
        )
        let paths = library.cells[0].elements.compactMap { element -> IRPath? in
            if case .path(let path) = element { return path }
            return nil
        }

        #expect(paths.count == 2)
        #expect(paths[0].layer != paths[1].layer)

        let decoded = DEFIRConverter.toDEFDocument(library)
        #expect(decoded.nets[0].routing[0].layerName == "li1")
        #expect(decoded.nets[1].routing[0].layerName == "met1")
    }

    @Test func defRouteLayerRequiresExplicitMapping() throws {
        let original = DEFDocument(
            designName: "chip",
            nets: [
                DEFNet(
                    name: "sig",
                    routing: [
                        DEFRouteWire(
                            layerName: "met1",
                            points: [
                                IRPoint(x: 0, y: 0),
                                IRPoint(x: 100, y: 0),
                            ]
                        ),
                    ]
                ),
            ]
        )

        #expect(throws: DEFIRConverterError.missingLayerMapping(layerName: "met1")) {
            _ = try DEFIRConverter.toIRLibraryChecked(original)
        }
    }

    @Test func defRegularRouteWithTooFewPointsThrows() throws {
        let original = DEFDocument(
            designName: "chip",
            nets: [
                DEFNet(
                    name: "sig",
                    routing: [
                        DEFRouteWire(
                            layerName: "met1",
                            points: [
                                IRPoint(x: 0, y: 0),
                            ]
                        ),
                    ]
                ),
            ]
        )

        #expect(throws: DEFIRConverterError.invalidRouteGeometry(
            netName: "sig",
            layerName: "met1",
            reason: "DEF regular route requires at least two placement points."
        )) {
            _ = try DEFIRConverter.toIRLibraryChecked(
                original,
                layerNumbers: try DEFLayerNumberMapping(layerNumbersByName: ["met1": 1])
            )
        }
    }

    @Test func defSpecialRouteWithOnlyViaThrows() throws {
        let original = DEFDocument(
            designName: "chip",
            specialNets: [
                DEFSpecialNet(
                    name: "vdd",
                    routing: [
                        DEFRouteSegment(
                            layerName: "met1",
                            width: 100,
                            points: [
                                DEFRoutePoint(viaName: "VIA1"),
                            ]
                        ),
                    ]
                ),
            ]
        )

        #expect(throws: DEFIRConverterError.invalidRouteGeometry(
            netName: "vdd",
            layerName: "met1",
            reason: "DEF special route requires at least two placement points."
        )) {
            _ = try DEFIRConverter.toIRLibraryChecked(
                original,
                layerNumbers: try DEFLayerNumberMapping(layerNumbersByName: ["met1": 1])
            )
        }
    }

    @Test func defSpecialRouteWithZeroWidthThrows() throws {
        let original = DEFDocument(
            designName: "chip",
            specialNets: [
                DEFSpecialNet(
                    name: "vdd",
                    routing: [
                        DEFRouteSegment(
                            layerName: "met1",
                            width: 0,
                            points: [
                                DEFRoutePoint(x: 0, y: 0),
                                DEFRoutePoint(x: 100, y: 0),
                            ]
                        ),
                    ]
                ),
            ]
        )

        #expect(throws: DEFIRConverterError.invalidRouteGeometry(
            netName: "vdd",
            layerName: "met1",
            reason: "DEF special route requires a positive width."
        )) {
            _ = try DEFIRConverter.toIRLibraryChecked(
                original,
                layerNumbers: try DEFLayerNumberMapping(layerNumbersByName: ["met1": 1])
            )
        }
    }

    @Test func viaDefinitionsSurviveIRRoundTrip() throws {
        let original = DEFDocument(
            designName: "chip",
            dbuPerMicron: 1000,
            viaDefs: [
                DEFViaDef(
                    name: "DEFVIA",
                    layers: [
                        DEFViaLayer(
                            layerName: "metal1",
                            rects: [DEFRect(x1: -60, y1: -50, x2: 60, y2: 50)]
                        ),
                        DEFViaLayer(
                            layerName: "via1",
                            rects: [DEFRect(x1: -25, y1: -25, x2: 25, y2: 25)]
                        ),
                        DEFViaLayer(
                            layerName: "metal2",
                            rects: [DEFRect(x1: -70, y1: -65, x2: 70, y2: 65)]
                        ),
                    ],
                    cutSize: (width: 50, height: 50),
                    cutSpacing: (x: 100, y: 120),
                    botEnclosure: (x: 35, y: 25),
                    topEnclosure: (x: 45, y: 40),
                    rowCol: (rows: 1, cols: 1)
                ),
            ]
        )

        let library = try DEFIRConverter.toIRLibrary(original)
        let decoded = DEFIRConverter.toDEFDocument(library)

        #expect(decoded.viaDefs.count == 1)
        #expect(decoded.viaDefs[0].name == "DEFVIA")
        #expect(decoded.viaDefs[0].layers.count == 3)
        #expect(decoded.viaDefs[0].layers[1].layerName == "via1")
        #expect(decoded.viaDefs[0].layers[1].rects.first?.x1 == -25)
        #expect(decoded.viaDefs[0].cutSize?.width == 50)
        #expect(decoded.viaDefs[0].cutSpacing?.y == 120)
        #expect(decoded.viaDefs[0].botEnclosure?.x == 35)
        #expect(decoded.viaDefs[0].topEnclosure?.y == 40)
        #expect(decoded.viaDefs[0].rowCol?.cols == 1)
    }
}
