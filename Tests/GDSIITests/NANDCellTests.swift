import Testing
import Foundation
import LayoutIR
@testable import GDSII

@Suite("NAND Cell Round-Trip")
struct NANDCellTests {

    /// Build a simplified NAND2 memory cell with realistic layer structure.
    /// Layers: 1=Diffusion, 2=Poly, 3=Metal1, 4=Contact, 5=Via
    static func buildNAND2Library() -> IRLibrary {
        // Cell dimensions: ~2µm × 3µm at 1000 DBU/µm
        let diffLayer: Int16 = 1
        let polyLayer: Int16 = 2
        let metal1Layer: Int16 = 3
        let contactLayer: Int16 = 4

        var elements: [IRElement] = []

        // N-diffusion region (vertical strip)
        elements.append(.boundary(IRBoundary(
            layer: diffLayer, datatype: 0,
            points: [
                IRPoint(x: 400, y: 0),
                IRPoint(x: 1600, y: 0),
                IRPoint(x: 1600, y: 3000),
                IRPoint(x: 400, y: 3000),
                IRPoint(x: 400, y: 0),
            ],
            properties: []
        )))

        // Poly gate A (horizontal strip)
        elements.append(.boundary(IRBoundary(
            layer: polyLayer, datatype: 0,
            points: [
                IRPoint(x: 0, y: 600),
                IRPoint(x: 2000, y: 600),
                IRPoint(x: 2000, y: 900),
                IRPoint(x: 0, y: 900),
                IRPoint(x: 0, y: 600),
            ],
            properties: []
        )))

        // Poly gate B (horizontal strip)
        elements.append(.boundary(IRBoundary(
            layer: polyLayer, datatype: 0,
            points: [
                IRPoint(x: 0, y: 1600),
                IRPoint(x: 2000, y: 1600),
                IRPoint(x: 2000, y: 1900),
                IRPoint(x: 0, y: 1900),
                IRPoint(x: 0, y: 1600),
            ],
            properties: []
        )))

        // Contact: Source (bottom)
        elements.append(.boundary(IRBoundary(
            layer: contactLayer, datatype: 0,
            points: [
                IRPoint(x: 850, y: 100),
                IRPoint(x: 1150, y: 100),
                IRPoint(x: 1150, y: 400),
                IRPoint(x: 850, y: 400),
                IRPoint(x: 850, y: 100),
            ],
            properties: []
        )))

        // Contact: Middle (between gates)
        elements.append(.boundary(IRBoundary(
            layer: contactLayer, datatype: 0,
            points: [
                IRPoint(x: 850, y: 1100),
                IRPoint(x: 1150, y: 1100),
                IRPoint(x: 1150, y: 1400),
                IRPoint(x: 850, y: 1400),
                IRPoint(x: 850, y: 1100),
            ],
            properties: []
        )))

        // Contact: Drain (top)
        elements.append(.boundary(IRBoundary(
            layer: contactLayer, datatype: 0,
            points: [
                IRPoint(x: 850, y: 2200),
                IRPoint(x: 1150, y: 2200),
                IRPoint(x: 1150, y: 2500),
                IRPoint(x: 850, y: 2500),
                IRPoint(x: 850, y: 2200),
            ],
            properties: []
        )))

        // Metal1 routing: GND rail (bottom)
        elements.append(.path(IRPath(
            layer: metal1Layer, datatype: 0,
            pathType: .halfWidthExtend,
            width: 200,
            points: [IRPoint(x: 0, y: 200), IRPoint(x: 2000, y: 200)],
            properties: []
        )))

        // Metal1 routing: VDD rail (top)
        elements.append(.path(IRPath(
            layer: metal1Layer, datatype: 0,
            pathType: .halfWidthExtend,
            width: 200,
            points: [IRPoint(x: 0, y: 2800), IRPoint(x: 2000, y: 2800)],
            properties: []
        )))

        // Labels
        elements.append(.text(IRText(
            layer: polyLayer, texttype: 0,
            transform: .identity,
            position: IRPoint(x: -200, y: 750),
            string: "A",
            properties: []
        )))

        elements.append(.text(IRText(
            layer: polyLayer, texttype: 0,
            transform: .identity,
            position: IRPoint(x: -200, y: 1750),
            string: "B",
            properties: []
        )))

        elements.append(.text(IRText(
            layer: metal1Layer, texttype: 0,
            transform: .identity,
            position: IRPoint(x: 1000, y: 200),
            string: "GND",
            properties: []
        )))

        elements.append(.text(IRText(
            layer: metal1Layer, texttype: 0,
            transform: .identity,
            position: IRPoint(x: 1000, y: 2800),
            string: "VDD",
            properties: []
        )))

        let nandCell = IRCell(name: "NAND2", elements: elements)

        return IRLibrary(
            name: "NANDLIB",
            units: IRUnits(dbuPerMicron: 1000),
            cells: [nandCell]
        )
    }

    @Test func nandCellConstruction() {
        let lib = NANDCellTests.buildNAND2Library()
        #expect(lib.cells.count == 1)
        #expect(lib.cells[0].name == "NAND2")
        #expect(lib.cells[0].elements.count == 12)
    }

    @Test func nandCellGDSIIRoundTrip() throws {
        let original = NANDCellTests.buildNAND2Library()

        // Write to GDSII
        let data = try GDSLibraryWriter.write(original)
        #expect(data.count > 0)

        // Read back
        let result = try GDSLibraryReader.read(data)

        // Verify library
        #expect(result.name == "NANDLIB")
        #expect(result.cells.count == 1)

        let cell = result.cells[0]
        #expect(cell.name == "NAND2")
        #expect(cell.elements.count == original.cells[0].elements.count)

        // Verify each element type count
        var boundaryCount = 0
        var pathCount = 0
        var textCount = 0
        for element in cell.elements {
            switch element {
            case .boundary: boundaryCount += 1
            case .path: pathCount += 1
            case .text: textCount += 1
            default: break
            }
        }
        #expect(boundaryCount == 6)  // 1 diffusion + 2 poly + 3 contacts
        #expect(pathCount == 2)       // GND + VDD rails
        #expect(textCount == 4)       // A, B, GND, VDD
    }

    @Test func nandCellPointsPreserved() throws {
        let original = NANDCellTests.buildNAND2Library()
        let data = try GDSLibraryWriter.write(original)
        let result = try GDSLibraryReader.read(data)

        // Check diffusion boundary points are preserved exactly
        if case .boundary(let b) = result.cells[0].elements[0] {
            #expect(b.layer == 1) // diffusion
            #expect(b.points == [
                IRPoint(x: 400, y: 0),
                IRPoint(x: 1600, y: 0),
                IRPoint(x: 1600, y: 3000),
                IRPoint(x: 400, y: 3000),
                IRPoint(x: 400, y: 0),
            ])
        } else {
            Issue.record("Expected boundary as first element")
        }
    }

    @Test func nandCellTextPreserved() throws {
        let original = NANDCellTests.buildNAND2Library()
        let data = try GDSLibraryWriter.write(original)
        let result = try GDSLibraryReader.read(data)

        // Find "A" label
        let texts = result.cells[0].elements.compactMap { element -> IRText? in
            if case .text(let t) = element { return t }
            return nil
        }
        #expect(texts.count == 4)

        let labelA = texts.first { $0.string == "A" }
        #expect(labelA != nil)
        #expect(labelA?.position == IRPoint(x: -200, y: 750))
        #expect(labelA?.layer == 2)
    }

    @Test func nandCellDoubleRoundTrip() throws {
        let original = NANDCellTests.buildNAND2Library()

        // Write → Read → Write → Read
        let data1 = try GDSLibraryWriter.write(original)
        let result1 = try GDSLibraryReader.read(data1)
        let data2 = try GDSLibraryWriter.write(result1)
        let result2 = try GDSLibraryReader.read(data2)

        // After first round-trip, subsequent trips should be binary-identical
        // (first trip may differ due to Real8 precision on units)
        let data3 = try GDSLibraryWriter.write(result2)
        #expect(data2 == data3)

        // IR structure should match
        #expect(result2.cells.count == result1.cells.count)
        #expect(result2.cells[0].elements.count == result1.cells[0].elements.count)
        #expect(result2.name == result1.name)
    }

    @Test func nandCellWithHierarchy() throws {
        // Create a NAND cell and instantiate it in a top cell
        let nandLib = NANDCellTests.buildNAND2Library()
        let nandCell = nandLib.cells[0]

        let topCell = IRCell(name: "TOP", elements: [
            .cellRef(IRCellRef(
                cellName: "NAND2",
                origin: IRPoint(x: 0, y: 0),
                transform: .identity,
                properties: []
            )),
            .cellRef(IRCellRef(
                cellName: "NAND2",
                origin: IRPoint(x: 3000, y: 0),
                transform: IRTransform(mirrorX: true),
                properties: []
            )),
        ])

        let lib = IRLibrary(
            name: "NANDTOP",
            units: IRUnits(dbuPerMicron: 1000),
            cells: [nandCell, topCell]
        )

        let data = try GDSLibraryWriter.write(lib)
        let result = try GDSLibraryReader.read(data)

        #expect(result.cells.count == 2)
        let top = result.cell(named: "TOP")
        #expect(top != nil)
        #expect(top?.elements.count == 2)

        if case .cellRef(let ref) = top?.elements[1] {
            #expect(ref.cellName == "NAND2")
            #expect(ref.origin == IRPoint(x: 3000, y: 0))
            #expect(ref.transform.mirrorX == true)
        } else {
            Issue.record("Expected cellRef at index 1")
        }
    }
}
