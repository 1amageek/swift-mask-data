import CircuiteFoundation
import Foundation
import Testing
import LayoutIR
import GDSII
import OASIS
import LEF
import CIF
import DXF

@Suite("Via placement codec contract")
struct ViaPlacementCodecTests {
    private func library() throws -> IRLibrary {
        IRLibrary(name: "top", databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 2000),
            cells: [IRCell(name: "top", elements: [
                .boundary(IRBoundary(layer: 1, datatype: 0, points: [IRPoint(x: 0, y: 0), IRPoint(x: 10, y: 0), IRPoint(x: 10, y: 10), IRPoint(x: 0, y: 0)])),
                .via(IRVia(viaName: "hv", origin: IRPoint(x: -6500, y: 3300),
                    transform: IRTransform(mirrorX: true, angle: 90), routeLayer: 7,
                    properties: [IRProperty(attribute: 0, value: "def.route.netName=N")]))])])
    }

    @Test func ownedTypedPlacementCodableRetainsEveryField() throws {
        let input = try library()
        let decoded = try JSONDecoder().decode(IRLibrary.self, from: JSONEncoder().encode(input))
        #expect(decoded == input)
    }

    @Test func unresolvedViaRejectsEveryOutputWithoutPublishingPartialValue() throws {
        let input = try library()
        var data: Data?
        do { data = try GDSLibraryWriter.write(input); Issue.record("GDS via unexpectedly serialized") }
        catch GDSError.unsupportedGeometry(let context, _) { #expect(context == "via") }
        #expect(data == nil)
        do { data = try OASISLibraryWriter.write(input); Issue.record("OASIS via unexpectedly serialized") }
        catch OASISError.unsupportedGeometry(let context, _) { #expect(context == "via") }
        #expect(data == nil)
        do { data = try CIFLibraryWriter.write(input); Issue.record("CIF via unexpectedly serialized") }
        catch CIFError.unsupportedGeometry { }
        #expect(data == nil)
        do { data = try DXFLibraryWriter.write(input); Issue.record("DXF via unexpectedly serialized") }
        catch DXFError.unsupportedEntity { }
        #expect(data == nil)
        var document: LEFDocument?
        do { document = try LEFIRConverter.toLEFDocument(input); Issue.record("LEF via unexpectedly omitted") }
        catch LEFError.invalidGeometry { }
        #expect(document == nil)
    }
}
