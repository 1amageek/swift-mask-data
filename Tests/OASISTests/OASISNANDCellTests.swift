import Testing
import Foundation
import LayoutIR
@testable import OASIS
@testable import GDSII

// MARK: - Step 12: NAND2 OASIS Round-Trip

@Suite("NAND Cell OASIS Round-Trip")
struct OASISNANDCellTests {

    /// Reuse the same NAND2 library as GDSIITests.
    static func buildNAND2Library() -> IRLibrary {
        let diffLayer: Int16 = 1
        let polyLayer: Int16 = 2
        let metal1Layer: Int16 = 3
        let contactLayer: Int16 = 4

        var elements: [IRElement] = []

        // N-diffusion region
        elements.append(.boundary(IRBoundary(
            layer: diffLayer, datatype: 0,
            points: [
                IRPoint(x: 400, y: 0), IRPoint(x: 1600, y: 0),
                IRPoint(x: 1600, y: 3000), IRPoint(x: 400, y: 3000),
                IRPoint(x: 400, y: 0),
            ],
            properties: []
        )))

        // Poly gate A
        elements.append(.boundary(IRBoundary(
            layer: polyLayer, datatype: 0,
            points: [
                IRPoint(x: 0, y: 600), IRPoint(x: 2000, y: 600),
                IRPoint(x: 2000, y: 900), IRPoint(x: 0, y: 900),
                IRPoint(x: 0, y: 600),
            ],
            properties: []
        )))

        // Poly gate B
        elements.append(.boundary(IRBoundary(
            layer: polyLayer, datatype: 0,
            points: [
                IRPoint(x: 0, y: 1600), IRPoint(x: 2000, y: 1600),
                IRPoint(x: 2000, y: 1900), IRPoint(x: 0, y: 1900),
                IRPoint(x: 0, y: 1600),
            ],
            properties: []
        )))

        // Contacts
        for (bx, by) in [(850, 100), (850, 1100), (850, 2200)] as [(Int32, Int32)] {
            elements.append(.boundary(IRBoundary(
                layer: contactLayer, datatype: 0,
                points: [
                    IRPoint(x: bx, y: by), IRPoint(x: bx + 300, y: by),
                    IRPoint(x: bx + 300, y: by + 300), IRPoint(x: bx, y: by + 300),
                    IRPoint(x: bx, y: by),
                ],
                properties: []
            )))
        }

        // Metal1 paths
        elements.append(.path(IRPath(
            layer: metal1Layer, datatype: 0,
            pathType: .halfWidthExtend, width: 200,
            points: [IRPoint(x: 0, y: 200), IRPoint(x: 2000, y: 200)],
            properties: []
        )))
        elements.append(.path(IRPath(
            layer: metal1Layer, datatype: 0,
            pathType: .halfWidthExtend, width: 200,
            points: [IRPoint(x: 0, y: 2800), IRPoint(x: 2000, y: 2800)],
            properties: []
        )))

        // Labels
        elements.append(.text(IRText(layer: polyLayer, texttype: 0, transform: .identity,
                                     position: IRPoint(x: -200, y: 750), string: "A", properties: [])))
        elements.append(.text(IRText(layer: polyLayer, texttype: 0, transform: .identity,
                                     position: IRPoint(x: -200, y: 1750), string: "B", properties: [])))
        elements.append(.text(IRText(layer: metal1Layer, texttype: 0, transform: .identity,
                                     position: IRPoint(x: 1000, y: 200), string: "GND", properties: [])))
        elements.append(.text(IRText(layer: metal1Layer, texttype: 0, transform: .identity,
                                     position: IRPoint(x: 1000, y: 2800), string: "VDD", properties: [])))

        let nandCell = IRCell(name: "NAND2", elements: elements)
        return IRLibrary(name: "NANDLIB", units: IRUnits(dbuPerMicron: 1000), cells: [nandCell])
    }

    @Test func nandCellOASISRoundTrip() throws {
        let original = OASISNANDCellTests.buildNAND2Library()

        let data = try OASISLibraryWriter.write(original)
        #expect(data.count > 0)

        let result = try OASISLibraryReader.read(data)

        #expect(result.name == "NANDLIB")
        #expect(result.cells.count == 1)

        let cell = result.cells[0]
        #expect(cell.name == "NAND2")
        #expect(cell.elements.count == original.cells[0].elements.count)

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
        #expect(boundaryCount == 6)
        #expect(pathCount == 2)
        #expect(textCount == 4)
    }

    @Test func nandCellPointsPreserved() throws {
        let original = OASISNANDCellTests.buildNAND2Library()
        let data = try OASISLibraryWriter.write(original)
        let result = try OASISLibraryReader.read(data)

        // Check diffusion boundary points are preserved exactly
        if case .boundary(let b) = result.cells[0].elements[0] {
            #expect(b.layer == 1)
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
        let original = OASISNANDCellTests.buildNAND2Library()
        let data = try OASISLibraryWriter.write(original)
        let result = try OASISLibraryReader.read(data)

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
        let original = OASISNANDCellTests.buildNAND2Library()

        let data1 = try OASISLibraryWriter.write(original)
        let result1 = try OASISLibraryReader.read(data1)
        let data2 = try OASISLibraryWriter.write(result1)
        let result2 = try OASISLibraryReader.read(data2)

        // After first round-trip, subsequent trips should be binary-identical
        let data3 = try OASISLibraryWriter.write(result2)
        #expect(data2 == data3)

        #expect(result2.cells.count == result1.cells.count)
        #expect(result2.cells[0].elements.count == result1.cells[0].elements.count)
        #expect(result2.name == result1.name)
    }

    @Test func nandCellWithHierarchy() throws {
        let nandLib = OASISNANDCellTests.buildNAND2Library()
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

        let data = try OASISLibraryWriter.write(lib)
        let result = try OASISLibraryReader.read(data)

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

// MARK: - Step 13: Cross-Format Tests

@Suite("GDSII-OASIS Cross-Format")
struct CrossFormatTests {

    @Test func gdsiiToOASISRoundTrip() throws {
        let original = OASISNANDCellTests.buildNAND2Library()

        // GDSII → IR
        let gdsData = try GDSLibraryWriter.write(original)
        let fromGDS = try GDSLibraryReader.read(gdsData)

        // IR → OASIS → IR
        let oasisData = try OASISLibraryWriter.write(fromGDS)
        let fromOASIS = try OASISLibraryReader.read(oasisData)

        // Compare cell names and element counts
        #expect(fromOASIS.cells.count == fromGDS.cells.count)
        #expect(fromOASIS.cells[0].name == fromGDS.cells[0].name)
        #expect(fromOASIS.cells[0].elements.count == fromGDS.cells[0].elements.count)
    }

    @Test func oasisToGDSIIRoundTrip() throws {
        let original = OASISNANDCellTests.buildNAND2Library()

        // OASIS → IR
        let oasisData = try OASISLibraryWriter.write(original)
        let fromOASIS = try OASISLibraryReader.read(oasisData)

        // IR → GDSII → IR
        let gdsData = try GDSLibraryWriter.write(fromOASIS)
        let fromGDS = try GDSLibraryReader.read(gdsData)

        // Compare cell names and element counts
        #expect(fromGDS.cells.count == fromOASIS.cells.count)
        #expect(fromGDS.cells[0].name == fromOASIS.cells[0].name)
        #expect(fromGDS.cells[0].elements.count == fromOASIS.cells[0].elements.count)
    }

    @Test func crossFormatElementTypesPreserved() throws {
        let original = OASISNANDCellTests.buildNAND2Library()

        // GDSII path
        let gdsData = try GDSLibraryWriter.write(original)
        let gdsLib = try GDSLibraryReader.read(gdsData)

        // OASIS path
        let oasisData = try OASISLibraryWriter.write(original)
        let oasisLib = try OASISLibraryReader.read(oasisData)

        // Both should have same element type distribution
        func countTypes(_ cell: IRCell) -> (boundary: Int, path: Int, text: Int) {
            var b = 0, p = 0, t = 0
            for e in cell.elements {
                switch e {
                case .boundary: b += 1
                case .path: p += 1
                case .text: t += 1
                default: break
                }
            }
            return (b, p, t)
        }

        let gdsTypes = countTypes(gdsLib.cells[0])
        let oasisTypes = countTypes(oasisLib.cells[0])

        #expect(gdsTypes.boundary == oasisTypes.boundary)
        #expect(gdsTypes.path == oasisTypes.path)
        #expect(gdsTypes.text == oasisTypes.text)
    }

    @Test func crossFormatCoordinatesMatch() throws {
        let original = OASISNANDCellTests.buildNAND2Library()

        let gdsData = try GDSLibraryWriter.write(original)
        let gdsLib = try GDSLibraryReader.read(gdsData)

        let oasisData = try OASISLibraryWriter.write(original)
        let oasisLib = try OASISLibraryReader.read(oasisData)

        // Compare first boundary (diffusion) points
        if case .boundary(let gdsB) = gdsLib.cells[0].elements[0],
           case .boundary(let oasisB) = oasisLib.cells[0].elements[0] {
            #expect(gdsB.points == oasisB.points)
            #expect(gdsB.layer == oasisB.layer)
        } else {
            Issue.record("Expected boundary elements")
        }

        // Compare text strings
        let gdsTexts = gdsLib.cells[0].elements.compactMap { e -> IRText? in
            if case .text(let t) = e { return t } else { return nil }
        }.sorted { $0.string < $1.string }

        let oasisTexts = oasisLib.cells[0].elements.compactMap { e -> IRText? in
            if case .text(let t) = e { return t } else { return nil }
        }.sorted { $0.string < $1.string }

        #expect(gdsTexts.count == oasisTexts.count)
        for (g, o) in zip(gdsTexts, oasisTexts) {
            #expect(g.string == o.string)
            #expect(g.position == o.position)
        }
    }
}
