import CircuiteFoundation
import Foundation
import LayoutIR
import LEF
import Testing

@Suite("LEF geometry preservation")
struct LEFGeometryPreservationTests {
    @Test func nonrectangularBoundaryRetainsItsPerimeterInStandardBytes() throws {
        let points = [IRPoint(x: 0, y: 0), IRPoint(x: 1000, y: 0), IRPoint(x: 1000, y: 500),
            IRPoint(x: 500, y: 500), IRPoint(x: 500, y: 1000), IRPoint(x: 0, y: 1000), IRPoint(x: 0, y: 0)]
        let source = try library(element: .boundary(IRBoundary(layer: 1, datatype: 0, points: points)))
        let bytes = try LEFLibraryWriter.write(LEFIRConverter.toLEFDocument(source))
        #expect(String(decoding: bytes, as: UTF8.self).contains("POLYGON"))
        let result = try LEFIRConverter.toIRLibrary(LEFLibraryReader.read(bytes))
        guard case .boundary(let boundary) = result.cells[0].elements[0] else {
            Issue.record("Expected exact polygon")
            return
        }
        #expect(boundary.points == points)
    }

    @Test func halfWidthPathUsesStandardWidthAndPathStatements() throws {
        let path = IRPath(layer: 1, datatype: 0, pathType: .halfWidthExtend, width: 100,
            points: [IRPoint(x: -500, y: 0), IRPoint(x: 1000, y: 0), IRPoint(x: 1000, y: 2000)])
        let bytes = try LEFLibraryWriter.write(LEFIRConverter.toLEFDocument(library(element: .path(path))))
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(text.contains("WIDTH 0.1"))
        #expect(text.contains("PATH -0.5 0 1 0 1 2"))
        let result = try LEFIRConverter.toIRLibrary(LEFLibraryReader.read(bytes))
        #expect(result.cells[0].elements == [.path(path)])
    }

    @Test func unsupportedOBSMeaningCannotBecomeEmptySuccess() throws {
        let elements: [IRElement] = [.text(IRText(layer: 1, position: IRPoint(x: 0, y: 0), string: "PORT")),
            .cellRef(IRCellRef(cellName: "CHILD", origin: IRPoint(x: 0, y: 0))),
            .path(IRPath(layer: 1, datatype: 0, pathType: .round, width: 100,
                points: [IRPoint(x: 0, y: 0), IRPoint(x: 1000, y: 0)]))]
        for element in elements {
            #expect(throws: LEFError.self) { _ = try LEFIRConverter.toLEFDocument(library(element: element)) }
        }
        let annotated = IRBoundary(layer: 1, datatype: 1,
            points: [IRPoint(x: 0, y: 0), IRPoint(x: 1000, y: 0), IRPoint(x: 1000, y: 1000)])
        #expect(throws: LEFError.self) { _ = try LEFIRConverter.toLEFDocument(library(element: .boundary(annotated))) }
    }

    @Test func literalSourcePathRequiresWidthAndRetainsWidthChanges() throws {
        let data = Data("""
        VERSION 5.8 ;
        UNITS DATABASE MICRONS 1000 ; END UNITS
        LAYER M1 TYPE ROUTING ; END M1
        MACRO TOP
        OBS LAYER M1 ; WIDTH 0.1 ; PATH 0 0 1 0 ; WIDTH 0.2 ; PATH 1 0 1 2 ; END
        END TOP
        END LIBRARY
        """.utf8)
        let result = try LEFIRConverter.toIRLibrary(LEFLibraryReader.read(data))
        let paths = result.cells[0].elements.compactMap { element -> IRPath? in
            if case .path(let path) = element { return path }
            return nil
        }
        #expect(paths.map(\.width) == [100, 200])
        #expect(paths.allSatisfy { $0.pathType == .halfWidthExtend })
        let missingWidth = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "WIDTH 0.1 ; ", with: "").utf8)
        #expect(throws: LEFError.self) { _ = try LEFLibraryReader.read(missingWidth) }
        let resetWidth = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "WIDTH 0.2 ;", with: "LAYER M1 ;").utf8)
        #expect(throws: LEFError.self) { _ = try LEFLibraryReader.read(resetWidth) }
    }

    @Test func customCapsBecomeExactSurfacesAndOverflowRefuses() throws {
        let path = IRPath(layer: 1, datatype: 0, pathType: .customExtension, width: 100,
            points: [IRPoint(x: 1000, y: 0), IRPoint(x: 0, y: 0), IRPoint(x: 0, y: 2000)],
            beginExtension: 200, endExtension: -100)
        let bytes = try LEFLibraryWriter.write(LEFIRConverter.toLEFDocument(library(element: .path(path))))
        let parsed = try LEFLibraryReader.read(bytes)
        #expect(parsed.macros[0].obs[0].rects == [LEFRect(x1: -0.05, y1: -0.05, x2: 1.2, y2: 0.05),
            LEFRect(x1: -0.05, y1: -0.05, x2: 0.05, y2: 1.9)])
        let shapes = try LEFIRConverter.toIRLibrary(parsed).cells[0].elements
        #expect(shapes.count == 2)
        guard case .boundary(let first) = shapes[0], case .boundary(let second) = shapes[1] else {
            Issue.record("Expected actual custom-cap rectangles")
            return
        }
        #expect(first.points == [IRPoint(x: -50, y: -50), IRPoint(x: 1200, y: -50), IRPoint(x: 1200, y: 50), IRPoint(x: -50, y: 50), IRPoint(x: -50, y: -50)])
        #expect(second.points[2] == IRPoint(x: 50, y: 1900))
        let overflow = IRPath(layer: 1, datatype: 0, width: 100,
            points: [IRPoint(x: 0, y: .max), IRPoint(x: 1000, y: .max)])
        #expect(throws: LEFError.self) { _ = try LEFIRConverter.toLEFDocument(library(element: .path(overflow))) }
    }

    @Test func pathSchemaDecodesPreviousPortsAndRoundTripsNewPorts() throws {
        let previousInitializer = LEFPort.init(layerName:rects:polygons:vias:portClass:)
        #expect(previousInitializer("M1", [], [], [], nil).paths.isEmpty)
        let oldBytes = Data("{\"layerName\":\"M1\",\"rects\":[],\"polygons\":[],\"vias\":[]}".utf8)
        let old = try JSONDecoder().decode(LEFPort.self, from: oldBytes)
        #expect(old.paths.isEmpty)
        var port = old
        port.paths = [LEFPath(width: 0.1, points: [LEFPoint(x: 0, y: 0), LEFPoint(x: 1, y: 0)])]
        #expect(try JSONDecoder().decode(LEFPort.self, from: JSONEncoder().encode(port)) == port)
    }

    @Test func sourceViaDeclarationIsRetainedButUnresolvedProjectionRefuses() throws {
        let bytes = Data("""
        VERSION 5.8 ;
        LAYER M1 TYPE ROUTING ; END M1
        MACRO TOP PIN A PORT LAYER M1 ; RECT 0 0 1 1 ; VIA 0.5 0.5 V1 ; END END A END TOP
        END LIBRARY
        """.utf8)
        let source = try LEFLibraryReader.read(bytes)
        #expect(source.macros[0].pins[0].ports[0].vias == [LEFPortVia(viaName: "V1", point: LEFPoint(x: 0.5, y: 0.5))])
        let restored = try LEFLibraryReader.read(LEFLibraryWriter.write(source))
        #expect(restored.macros[0].pins == source.macros[0].pins)
        #expect(throws: LEFError.self) { _ = try LEFIRConverter.toIRLibrary(source) }
    }

    private func library(element: IRElement) throws -> IRLibrary {
        IRLibrary(name: "PRESERVE", databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1000),
            cells: [IRCell(name: "TOP", elements: [element])])
    }
}
