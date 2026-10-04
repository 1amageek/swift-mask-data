import Foundation
import Testing
import LayoutIR
@testable import DEF

@Suite("DEF standalone via placement")
struct DEFStandaloneViaTests {
    @Test func actualNativeStandaloneViaIsNotAZeroLengthWire() throws {
        let bytes = Data("VERSION 5.8 ; DESIGN top ; UNITS DISTANCE MICRONS 1000 ; NETS 1 ; - N ( U1 Y ) ( U2 A ) + ROUTED metH ( 6500 3300 ) hv ; END NETS END DESIGN".utf8)
        let doc = try DEFLibraryReader.read(bytes)
        let lib = try DEFIRConverter.toIRLibrary(doc, layerNumbers: DEFLayerNumberMapping(layerNumbersByName: ["metH": 7]))
        let roundtrip = try DEFIRConverter.toDEFDocument(lib)
        #expect(roundtrip.nets[0].routing[0].points == [IRPoint(x: 6500, y: 3300)])
        #expect(roundtrip.nets[0].routing[0].viaName == "hv")
        #expect(!lib.cells[0].elements.contains { if case .path = $0 { true } else { false } })
    }
    @Test(arguments: ["N", "S", "E", "W", "FN", "FS", "FE", "FW"])
    func orientationsRetainUnitsLayersAndProvenance(_ orientation: String) throws {
        for special in [false, true] {
            let section = special ? "SPECIALNETS" : "NETS"
            let width = special ? " 20" : ""
            let bytes = Data("VERSION 5.8 ; DESIGN top ; UNITS DISTANCE MICRONS 2000 ; \(section) 1 ; - N ( U1 Y ) + ROUTED metH\(width) ( -6500 3300 ) hv \(orientation) ; END \(section) END DESIGN".utf8)
            let doc = try DEFLibraryReader.read(bytes)
            let lib = try DEFIRConverter.toIRLibrary(doc, layerNumbers: DEFLayerNumberMapping(layerNumbersByName: ["metH": 7]))
            let via = try #require(lib.cells[0].elements.compactMap { if case .via(let via) = $0 { via } else { nil } }.first)
            #expect(lib.databaseUnitScale.databaseUnitsPerMicrometer == 2000)
            #expect(via.viaName == "hv")
            #expect(via.origin == IRPoint(x: -6500, y: 3300))
            #expect(via.routeLayer == 7)
            #expect(via.transform == DEFIRConverter.orientationToTransform(try #require(DEFOrientation(rawValue: orientation))))
            #expect(via.properties.contains(IRProperty(attribute: 0, value: "def.route.netName=N")))
            let decoded = try DEFLibraryReader.read(DEFLibraryWriter.write(DEFIRConverter.toDEFDocument(lib)))
            let retained = try DEFIRConverter.toIRLibrary(decoded, layerNumbers: DEFLayerNumberMapping(layerNumbersByName: ["metH": 7]))
            #expect(retained.cells[0].elements == lib.cells[0].elements)
        }
    }

    @Test func terminalViaIsSeparateAndNeverDuplicated() throws {
        for special in [false, true] {
            let section = special ? "SPECIALNETS" : "NETS"
            let width = special ? " 20" : ""
            let bytes = Data("VERSION 5.8 ; DESIGN top ; \(section) 1 ; - N + ROUTED metH\(width) ( 0 0 ) ( 100 0 ) hv FW ; END \(section) END DESIGN".utf8)
            let doc = try DEFLibraryReader.read(bytes)
            let mapping = try DEFLayerNumberMapping(layerNumbersByName: ["metH": 7])
            let lib = try DEFIRConverter.toIRLibrary(doc, layerNumbers: mapping)
            #expect(lib.cells[0].elements.count == 2)
            let via = try #require(lib.cells[0].elements.compactMap { if case .via(let via) = $0 { via } else { nil } }.first)
            #expect(via.origin == IRPoint(x: 100, y: 0))
            let output = try DEFLibraryReader.read(DEFLibraryWriter.write(DEFIRConverter.toDEFDocument(lib)))
            let reparsed = try DEFIRConverter.toIRLibrary(output, layerNumbers: mapping)
            #expect(reparsed.cells[0].elements == lib.cells[0].elements)
        }
    }

    @Test func malformedAndUnrepresentablePlacementsFailExplicitly() throws {
        for route in ["( 10 20 )", "( 10 20 0 ) hv", "( 10 20 ) hv MASK 1", "( 10 20 ) hv BAD"] {
            let bytes = Data("VERSION 5.8 ; DESIGN top ; NETS 1 ; - N + ROUTED metH \(route) ; END NETS END DESIGN".utf8)
            #expect(throws: (any Error).self) {
                try DEFIRConverter.toIRLibrary(DEFLibraryReader.read(bytes), layerNumbers: DEFLayerNumberMapping(layerNumbersByName: ["metH": 7]))
            }
        }
        let source = Data("VERSION 5.8 ; DESIGN top ; NETS 1 ; - N + ROUTED metH ( 10 20 ) hv ; END NETS END DESIGN".utf8)
        var lib = try DEFIRConverter.toIRLibrary(DEFLibraryReader.read(source), layerNumbers: DEFLayerNumberMapping(layerNumbersByName: ["metH": 7]))
        let via = try #require(lib.cells[0].elements.compactMap { if case .via(let via) = $0 { via } else { nil } }.first)
        lib.cells[0].elements = [.via(IRVia(viaName: via.viaName, origin: via.origin,
            transform: IRTransform(angle: 45), routeLayer: via.routeLayer, properties: via.properties))]
        #expect(throws: DEFIRConverterError.unrepresentableTransform) { try DEFIRConverter.toDEFDocument(lib) }
        lib.cells[0].elements = [.via(IRVia(viaName: "hv", origin: via.origin, routeLayer: 7))]
        #expect(throws: (any Error).self) { try DEFIRConverter.toDEFDocument(lib) }
    }

    @Test func actualNativeFourViaRecordsRetainExactPlacementOrder() throws {
        let bytes = Data("VERSION 5.8 ; DESIGN top ; UNITS DISTANCE MICRONS 1000 ; NETS 1 ; - N ( U1 Y ) ( U2 A ) + ROUTED metH ( 6500 3300 ) hv + ROUTED metH ( 6500 900 ) hv + ROUTED metH ( 2900 900 ) hv + ROUTED metH ( 2900 1300 ) hv ; END NETS END DESIGN".utf8)
        let mapping = try DEFLayerNumberMapping(layerNumbersByName: ["metH": 7])
        let lib = try DEFIRConverter.toIRLibrary(DEFLibraryReader.read(bytes), layerNumbers: mapping)
        let vias = lib.cells[0].elements.compactMap { if case .via(let via) = $0 { via } else { nil } }
        #expect(vias.map(\.origin) == [IRPoint(x: 6500, y: 3300), IRPoint(x: 6500, y: 900), IRPoint(x: 2900, y: 900), IRPoint(x: 2900, y: 1300)])
        #expect(vias.allSatisfy { $0.viaName == "hv" && $0.routeLayer == 7 })
        let output = try DEFLibraryReader.read(DEFLibraryWriter.write(DEFIRConverter.toDEFDocument(lib)))
        #expect(output.nets[0].connections == [DEFConnection(componentName: "U1", pinName: "Y"), DEFConnection(componentName: "U2", pinName: "A")])
        #expect(try DEFIRConverter.toIRLibrary(output, layerNumbers: mapping).cells[0].elements == lib.cells[0].elements)
    }

    @Test func inverseRejectsHierarchicalOrMetadataOnlyViaRatherThanOmittingIt() throws {
        let source = Data("VERSION 5.8 ; DESIGN top ; NETS 1 ; - N + ROUTED metH ( 10 20 ) hv ; END NETS END DESIGN".utf8)
        var lib = try DEFIRConverter.toIRLibrary(DEFLibraryReader.read(source), layerNumbers: DEFLayerNumberMapping(layerNumbersByName: ["metH": 7]))
        let elements = lib.cells[0].elements
        lib.cells[0].elements = []
        lib.cells.append(IRCell(name: "child", elements: elements))
        #expect(throws: (any Error).self) { try DEFIRConverter.toDEFDocument(lib) }
        lib.cells = [IRCell(name: "top", elements: [.path(IRPath(layer: 7, datatype: 0,
            pathType: .halfWidthExtend, width: 1, points: [IRPoint(x: 0, y: 0), IRPoint(x: 100, y: 0)],
            properties: [IRProperty(attribute: 0, value: "def.route.viaName=hv")]))])]
        #expect(throws: (any Error).self) { try DEFIRConverter.toDEFDocument(lib) }
    }

}
