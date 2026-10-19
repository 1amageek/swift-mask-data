import CircuiteFoundation
import Foundation
import LayoutIR
import Testing
@testable import OASIS

@Suite("OASIS semantic preservation")
struct OASISSemanticPreservationTests {
    @Test func libraryMetadataRetainsNamesValuesAndScope() throws {
        var source = try library(elements: [.text(IRText(layer: 1, position: IRPoint(x: 0, y: 0), string: "PORT",
            properties: [IRProperty(attribute: 0, value: "owner=element")]))])
        source.metadata = ["owner": "library", "source=kind": "retained=value", "empty": ""]
        source.cells[0].properties = [IRProperty(attribute: 0, value: "owner=cell")]
        let restored = try OASISLibraryReader.read(OASISLibraryWriter.write(source))
        #expect(restored.metadata == source.metadata)
        #expect(restored.cells == source.cells)
    }

    @Test func unrepresentableLibraryPropertyValuesAndOwnersRefuse() throws {
        for variant in ["duplicate", "number", "multiple", "standard", "table"] {
            var writer = OASISWriter()
            writer.writeMagic(); writer.writeByte(1)
            try writer.writeAString("1.0"); writer.writeReal(1000); writer.writeUnsignedInteger(1)
            if variant == "table" {
                writer.writeByte(3)
                try writer.writeAString("TOP")
            }
            writer.writeByte(28)
            writer.writeByte(variant == "standard" ? 0x15 : variant == "multiple" ? 0x24 : 0x14)
            try writer.writeAString("owner")
            try writer.writePropertyValue(variant == "number" ? .unsignedInteger(7) : .aString("library"))
            if variant == "multiple" { try writer.writePropertyValue(.aString("second")) }
            if variant == "duplicate" { writer.writeByte(29) }
            writer.writeByte(2)
            for _ in 0..<12 { writer.writeUnsignedInteger(0) }
            writer.writeBString(Data(repeating: 0, count: 240)); writer.writeUnsignedInteger(0)
            #expect(throws: OASISError.self) { _ = try OASISLibraryReader.read(writer.data) }
        }
    }

    @Test func transformedTextIsRefused() throws {
        for transform in [IRTransform(mirrorX: true), IRTransform(magnification: 2), IRTransform(angle: 90)] {
            let library = try library(elements: [.text(IRText(layer: 1, transform: transform,
                position: IRPoint(x: 10, y: 20), string: "PORT"))])
            #expect(throws: OASISError.self) { _ = try OASISLibraryWriter.write(library) }
        }
    }

    @Test func cellAndElementNamedPropertiesRemainDistinct() throws {
        let cellProperties = [IRProperty(attribute: 0, value: "owner="),
            IRProperty(attribute: 0, value: "owner=second=value")]
        let elementProperties = [IRProperty(attribute: 0, value: "owner=element")]
        let text = IRText(layer: 1, position: IRPoint(x: -10, y: 20), string: "PORT",
            properties: elementProperties)
        var source = try library(elements: [.text(text)])
        source.cells[0].properties = cellProperties
        source.cells.append(IRCell(name: "EMPTY", properties: [IRProperty(attribute: 0, value: "scope=empty")]))
        let bytes = try OASISLibraryWriter.write(source)
        let result = try OASISLibraryReader.read(bytes)
        #expect(result.cells[0].properties == cellProperties)
        #expect(result.cells[0].elements == source.cells[0].elements)
        #expect(result.cells[1].properties == source.cells[1].properties)
    }

    @Test func literalCellPropertyRepeatDoesNotBecomeElementProperty() throws {
        var writer = OASISWriter()
        writer.writeMagic()
        writer.writeByte(1)
        try writer.writeAString("1.0")
        writer.writeReal(1000)
        writer.writeUnsignedInteger(1)
        writer.writeByte(14)
        try writer.writeAString("TOP")
        writer.writeByte(28)
        writer.writeByte(0x14)
        try writer.writeAString("owner")
        writer.writeUnsignedInteger(10)
        try writer.writeAString("cell")
        writer.writeByte(29)
        writer.writeByte(19)
        writer.writeByte(0x5f)
        try writer.writeAString("PORT")
        writer.writeUnsignedInteger(0)
        writer.writeUnsignedInteger(1)
        writer.writeSignedInteger(10)
        writer.writeSignedInteger(20)
        writer.writeUnsignedInteger(2)
        writer.writeUnsignedInteger(0)
        writer.writeUnsignedInteger(100)
        writer.writeByte(0) // PAD does not change the property owner.
        writer.writeByte(29)
        writer.writeByte(2)
        for _ in 0..<12 { writer.writeUnsignedInteger(0) }
        writer.writeBString(Data(repeating: 0, count: 240))
        writer.writeUnsignedInteger(0)
        let result = try OASISLibraryReader.read(writer.data)
        let expected = IRProperty(attribute: 0, value: "owner=cell")
        #expect(result.cells[0].properties == [expected, expected])
        guard case .text(let text) = result.cells[0].elements[0] else {
            Issue.record("Expected literal TEXT")
            return
        }
        #expect(text.properties == [expected])
        #expect(result.cells[0].elements.count == 2)
        guard case .text(let repeated) = result.cells[0].elements[1] else {
            Issue.record("Expected repeated TEXT")
            return
        }
        #expect(repeated.position == IRPoint(x: 110, y: 20))
        #expect(repeated.properties == [expected])
    }

    @Test func numericElementAttributesRetainNumberAndValue() throws {
        let text = IRText(layer: 1, position: IRPoint(x: 0, y: 0), string: "PORT",
            properties: [IRProperty(attribute: 7, value: "owner=element")])
        let source = try library(elements: [.text(text)])
        let result = try OASISLibraryReader.read(OASISLibraryWriter.write(source))
        #expect(result.cells[0].elements == source.cells[0].elements)
    }

    private func library(elements: [IRElement]) throws -> IRLibrary {
        IRLibrary(name: "PRESERVE", databaseUnitScale: try DatabaseUnitScale(databaseUnitsPerMicrometer: 1000),
            cells: [IRCell(name: "TOP", elements: elements)])
    }
}
