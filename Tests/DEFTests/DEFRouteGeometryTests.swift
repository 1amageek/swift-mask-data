import Foundation
import Testing
import LayoutIR
@testable import DEF

@Suite("DEF route geometry")
struct DEFRouteGeometryTests {
    private func library(_ routes: String, special: Bool = false, dbu: Int = 1000) throws -> IRLibrary {
        let section = special ? "SPECIALNETS" : "NETS"
        let source = "VERSION 5.8 ; DESIGN wire ; UNITS DISTANCE MICRONS \(dbu) ; \(section) 1 ; - n \(routes) ; END \(section) END DESIGN"
        return try DEFIRConverter.toIRLibrary(
            DEFLibraryReader.read(Data(source.utf8)),
            layerNumbers: DEFLayerNumberMapping(layerNumbersByName: ["metalA": 3, "metalB": 7]))
    }

    private func paths(_ library: IRLibrary) -> [IRPath] {
        library.cells[0].elements.compactMap { if case .path(let path) = $0 { path } else { nil } }
    }

    @Test func normalMissingExtensionsRemainSymbolic() throws {
        let path = try #require(paths(library("+ ROUTED metalA ( 10 20 ) ( 110 20 )")).first)
        #expect(path.pathType == .halfWidthExtend)
        #expect(path.layer == 3)
    }

    @Test func specialExplicitExtensionsBecomeGeometry() throws {
        let path = try #require(paths(library("+ ROUTED metalB 20 ( 10 20 3 ) ( 110 20 7 )", special: true)).first)
        #expect(path.pathType == .customExtension)
        #expect(path.beginExtension == 3)
        #expect(path.endExtension == 7)
    }

    @Test func explicitRegularCoordinatesDoNotBecomeViaOrConnections() throws {
        let source = "VERSION 5.8 ; DESIGN wire ; NETS 1 ; - n ( u A ) + ROUTED metalA ( 10 20 0 ) ( 110 * 7 ) V12 NEW metalB ( 110 20 ) ( * 120 ) ; END NETS END DESIGN"
        let doc = try DEFLibraryReader.read(Data(source.utf8))
        #expect(doc.nets[0].connections == [DEFConnection(componentName: "u", pinName: "A")])
        #expect(doc.nets[0].routing.count == 2)
        #expect(doc.nets[0].routing[0].pointExtensions == [0, 7])
        #expect(doc.nets[0].routing[0].viaName == "V12")
        #expect(doc.nets[0].routing[1].layerName == "metalB")
        #expect(doc.nets[0].routing[1].points == [IRPoint(x: 110, y: 20), IRPoint(x: 110, y: 120)])
        let lib = try DEFIRConverter.toIRLibrary(doc, layerNumbers: DEFLayerNumberMapping(layerNumbersByName: ["metalA": 3, "metalB": 7]))
        let routePaths = paths(lib)
        #expect(routePaths[0].pathType == .customExtension)
        #expect(routePaths[0].beginExtension == 0)
        #expect(routePaths[0].endExtension == 7)
        #expect(routePaths[1].pathType == .halfWidthExtend)
        let decoded = try DEFLibraryReader.read(DEFLibraryWriter.write(DEFIRConverter.toDEFDocument(lib)))
        #expect(decoded.nets[0].connections == doc.nets[0].connections)
        #expect(decoded.nets[0].routing[0].pointExtensions == [0, 7])
        #expect(decoded.nets[0].routing[0].viaName == nil)
        #expect(decoded.nets[0].routing[1].viaName == "V12")
        #expect(decoded.nets[0].routing[2].pointExtensions == [nil, nil])
    }

    @Test func specialMissingAndZeroExtensionsRemainFlush() throws {
        for coordinates in ["( 10 20 ) ( 110 20 )", "( 10 20 0 ) ( 110 20 0 )"] {
            let lib = try library("+ ROUTED metalA 20 \(coordinates)", special: true)
            #expect(paths(lib)[0].pathType == .flush)
            let converted = try DEFLibraryReader.read(DEFLibraryWriter.write(DEFIRConverter.toDEFDocument(lib)))
            #expect(converted.specialNets[0].routing[0].width == 20)
            #expect(converted.specialNets[0].routing[0].points[0].ext == (coordinates.contains("20 0") ? 0 : nil))
        }
    }

    @Test func segmentBoundariesPreserveInteriorPointExtensions() throws {
        let lib = try library("+ ROUTED metalA 20 ( 10 20 3 ) ( 110 20 7 ) ( * 120 0 )", special: true)
        let routePaths = paths(lib)
        #expect(routePaths.count == 2)
        #expect(routePaths[0].points == [IRPoint(x: 10, y: 20), IRPoint(x: 110, y: 20)])
        #expect(routePaths[0].beginExtension == 3)
        #expect(routePaths[0].endExtension == 7)
        #expect(routePaths[1].points == [IRPoint(x: 110, y: 20), IRPoint(x: 110, y: 120)])
        #expect(routePaths[1].beginExtension == 7)
        #expect(routePaths[1].endExtension == 0)
        let decoded = try DEFLibraryReader.read(DEFLibraryWriter.write(DEFIRConverter.toDEFDocument(lib)))
        #expect(paths(try DEFIRConverter.toIRLibrary(decoded, layerNumbers: DEFLayerNumberMapping(layerNumbersByName: ["metalA": 3]))) == routePaths)
    }

    @Test func extensionsRemainInSourceDBUAcrossUnitScales() throws {
        for dbu in [1000, 2000] {
            let lib = try library("+ ROUTED metalA ( 10 20 3 ) ( 110 20 7 )", dbu: dbu)
            #expect(lib.databaseUnitScale.databaseUnitsPerMicrometer == Double(dbu))
            #expect(paths(lib)[0].beginExtension == 3)
            #expect(paths(lib)[0].endExtension == 7)
            let inverse = try DEFIRConverter.toDEFDocument(lib)
            #expect(inverse.dbuPerMicron == Double(dbu))
            #expect(inverse.nets[0].routing[0].pointExtensions == [3, 7])
        }
    }

    @Test func rejectsUnrepresentableOrInvalidRouteProfiles() throws {
        #expect(throws: DEFIRConverterError.self) { try library("+ ROUTED metalA ( 10 20 0 ) ( 110 20 )") }
        #expect(throws: DEFIRConverterError.self) { try library("+ ROUTED metalA ( 10 20 ) ( 110 20 7 )") }
        #expect(throws: DEFIRConverterError.self) { try library("+ ROUTED metalA ( 10 20 ) ( 10 20 )") }
        #expect(throws: DEFIRConverterError.self) { try library("+ ROUTED metalA ( 10 20 ) ( 110 120 )") }
        #expect(throws: DEFIRConverterError.self) { try library("+ ROUTED metalA 21 ( 10 20 ) ( 110 20 )", special: true) }
        #expect(throws: DEFError.self) { try library("+ ROUTED metalA ( 10 20 -1 ) ( 110 20 0 )") }
        #expect(throws: DEFError.self) { try library("+ ROUTED metalA 20 ( 10 20 -1 ) ( 110 20 )", special: true) }
        for feature in ["TAPER", "TAPERRULE unknown", "STYLE 1", "MASK 2"] {
            #expect(throws: DEFError.self) { try library("+ ROUTED metalA \(feature) ( 10 20 ) ( 110 20 )") }
        }
        #expect(throws: DEFError.self) { try library("+ NONDEFAULTRULE wide + ROUTED metalA ( 10 20 ) ( 110 20 )") }
        #expect(throws: DEFError.self) { try library("+ ROUTED metalA ( 10 20 ) ( 110 20 ) + MASK 2") }
        #expect(throws: DEFError.self) { try library("+ ROUTED metalA 20 ( 10 20 ) ( 110 20 ) + TAPER", special: true) }
        #expect(throws: DEFError.self) { try library("+ ROUTED metalA ( 10 20 ) V12 ( 110 20 )") }
        #expect(throws: DEFError.self) { try library("+ ROUTED metalA ( * * ) ( 110 20 )") }
    }

    @Test func writerRejectsNegativeAndMisalignedExtensions() throws {
        let regular = DEFRouteWire(layerName: "metalA", points: [IRPoint(x: 10, y: 20), IRPoint(x: 110, y: 20)], pointExtensions: [-1, 0])
        #expect(throws: DEFError.self) { try DEFLibraryWriter.write(DEFDocument(nets: [DEFNet(name: "n", routing: [regular])])) }
        var invalid = regular
        invalid.pointExtensions = [0]
        #expect(throws: DEFError.self) { try DEFLibraryWriter.write(DEFDocument(nets: [DEFNet(name: "n", routing: [invalid])])) }
        let special = DEFRouteSegment(layerName: "metalA", width: 20, points: [DEFRoutePoint(x: 10, y: 20, ext: -1), DEFRoutePoint(x: 110, y: 20)])
        #expect(throws: DEFError.self) { try DEFLibraryWriter.write(DEFDocument(specialNets: [DEFSpecialNet(name: "n", routing: [special])])) }
    }

    @Test func inverseGeometryOverridesSourceExtensionMetadata() throws {
        var lib = try library("+ ROUTED metalA 20 ( 10 20 3 ) ( 110 20 7 )", special: true)
        var path = paths(lib)[0]
        path.beginExtension = 9
        path.endExtension = 11
        lib.cells[0].elements = [.path(path)]
        let decoded = try DEFIRConverter.toDEFDocument(lib)
        #expect(decoded.specialNets[0].routing[0].points[0].ext == 9)
        #expect(decoded.specialNets[0].routing[0].points[1].ext == 11)
        path.pathType = .round
        lib.cells[0].elements = [.path(path)]
        #expect(throws: DEFIRConverterError.self) { try DEFIRConverter.toDEFDocument(lib) }
    }
}
