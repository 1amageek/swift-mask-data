import CircuiteFoundation
import GDSII
import LayoutIR
import Testing

@Suite("GDS semantic preservation")
struct GDSSemanticPreservationTests {
    @Test func cellPropertiesAreRefusedWithoutAStandardCellPropertyRecord() throws {
        let library = IRLibrary(name: "PRESERVE", databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1000),
            cells: [IRCell(name: "TOP", properties: [IRProperty(attribute: 7, value: "owner=cell")])])
        #expect(throws: GDSError.self) { _ = try GDSLibraryWriter.write(library) }
    }

    @Test func elementPropertiesAndTextPoseArePreserved() throws {
        let properties = [IRProperty(attribute: 7, value: "owner=first"), IRProperty(attribute: 7, value: "owner=second")]
        let text = IRText(layer: 1, transform: IRTransform(mirrorX: true, magnification: 2, angle: 90),
            position: IRPoint(x: -10, y: 20), string: "PORT", properties: properties)
        let library = IRLibrary(name: "PRESERVE", databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1000),
            cells: [IRCell(name: "TOP", elements: [.text(text)])])
        let result = try GDSLibraryReader.read(GDSLibraryWriter.write(library))
        #expect(result.cells[0].elements == library.cells[0].elements)
    }
}
