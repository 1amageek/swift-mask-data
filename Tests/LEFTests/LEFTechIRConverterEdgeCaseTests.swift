import Testing
import Foundation
@testable import LEF
@testable import TechIR

@Suite("LEFTechIRConverter Edge Cases")
struct LEFTechIRConverterEdgeCaseTests {

    // MARK: - SpacingTable conversion

    @Test func spacingTableConversion() throws {
        let doc = LEFDocument(
            layers: [
                LEFLayerDef(
                    name: "M1",
                    type: .routing,
                    direction: .horizontal,
                    width: 0.14,
                    spacing: 0.14,
                    spacingTable: LEFSpacingTable(
                        parallelRunLengths: [0, 0.5, 1.0],
                        widthEntries: [
                            LEFSpacingTable.WidthEntry(width: 0.14, spacings: [0.14, 0.16, 0.18]),
                            LEFSpacingTable.WidthEntry(width: 0.28, spacings: [0.16, 0.18, 0.20]),
                        ]
                    )
                )
            ]
        )

        let lib = try LEFTechIRConverter.toIRTechLibrary(doc)

        #expect(lib.layers[0].spacingTable != nil)
        let table = lib.layers[0].spacingTable!
        #expect(table.entries.count == 2)
        #expect(table.entries[0].width == 0.14)
        #expect(table.entries[0].spacing == 0.14)
        #expect(table.entries[1].width == 0.28)
        #expect(table.entries[1].spacing == 0.16)
    }

    // MARK: - Layer with no design rule generated (all nil)

    @Test func layerNoDesignRule() throws {
        let doc = LEFDocument(
            layers: [
                LEFLayerDef(name: "OVERLAP1", type: .overlap)
            ]
        )

        let lib = try LEFTechIRConverter.toIRTechLibrary(doc)

        #expect(lib.layers.count == 1)
        #expect(lib.layers[0].type == .overlap)
        // No design rule: width is nil, spacing is nil, area is nil
        #expect(lib.designRules.isEmpty)
    }

    // MARK: - Via with 0 layers

    @Test func viaWithZeroLayers() throws {
        let doc = LEFDocument(
            vias: [
                LEFViaDef(name: "EMPTY_VIA", layers: [])
            ]
        )

        let lib = try LEFTechIRConverter.toIRTechLibrary(doc)

        #expect(lib.vias.count == 1)
        #expect(lib.vias[0].cutLayerName == "")
        #expect(lib.vias[0].topLayerName == "")
        #expect(lib.vias[0].bottomLayerName == "")
    }

    // MARK: - Via with 1 layer

    @Test func viaWithOneLayer() throws {
        let doc = LEFDocument(
            vias: [
                LEFViaDef(
                    name: "SINGLE_VIA",
                    layers: [
                        LEFViaDef.LEFViaLayer(layerName: "VIA1", rects: [])
                    ]
                )
            ]
        )

        let lib = try LEFTechIRConverter.toIRTechLibrary(doc)

        #expect(lib.vias[0].cutLayerName == "VIA1")
        #expect(lib.vias[0].topLayerName == "")
        #expect(lib.vias[0].bottomLayerName == "")
    }

    // MARK: - Via with cutSize and cutSpacing

    @Test func viaWithCutSizeAndSpacing() throws {
        let doc = LEFDocument(
            vias: [
                LEFViaDef(
                    name: "GEN_VIA",
                    layers: [
                        LEFViaDef.LEFViaLayer(layerName: "M1", rects: []),
                        LEFViaDef.LEFViaLayer(layerName: "VIA1", rects: []),
                        LEFViaDef.LEFViaLayer(layerName: "M2", rects: []),
                    ],
                    isGenerate: true,
                    cutSize: (0.15, 0.15),
                    cutSpacing: (0.17, 0.17),
                    enclosure: (0.05, 0.08, 0.05, 0.08),
                    resistance: 4.5
                )
            ]
        )

        let lib = try LEFTechIRConverter.toIRTechLibrary(doc)
        let via = lib.vias[0]

        #expect(via.cutWidth == 0.15)
        #expect(via.cutHeight == 0.15)
        #expect(via.spacing == 0.17)
        #expect(via.enclosure?.overhang1 == 0.05)
        #expect(via.enclosure?.overhang2 == 0.08)
        #expect(via.resistance == 4.5)
    }

    // MARK: - Enclosure rule from CUT layer

    @Test func enclosureRuleFromCutLayer() throws {
        let doc = LEFDocument(
            layers: [
                LEFLayerDef(
                    name: "VIA1",
                    type: .cut,
                    enclosure: LEFEnclosure(overhang1: 0.03, overhang2: 0.07)
                )
            ]
        )

        let lib = try LEFTechIRConverter.toIRTechLibrary(doc)

        #expect(lib.enclosureRules.count == 1)
        #expect(lib.enclosureRules[0].minEnclosure == 0.03) // min(0.03, 0.07)
    }

    // MARK: - Non-cut layer with enclosure produces no enclosure rule

    @Test func nonCutLayerNoEnclosureRule() throws {
        let doc = LEFDocument(
            layers: [
                LEFLayerDef(
                    name: "M1",
                    type: .routing,
                    enclosure: LEFEnclosure(overhang1: 0.05, overhang2: 0.05)
                )
            ]
        )

        let lib = try LEFTechIRConverter.toIRTechLibrary(doc)
        #expect(lib.enclosureRules.isEmpty)
    }

    // MARK: - Site with nil siteClass

    @Test func siteWithNilClass() throws {
        let doc = LEFDocument(
            sites: [
                LEFSiteDef(name: "CUSTOM_SITE", width: 0.5, height: 2.0)
            ]
        )

        let lib = try LEFTechIRConverter.toIRTechLibrary(doc)

        #expect(lib.sites.count == 1)
        #expect(lib.sites[0].siteClass == nil)
        #expect(lib.sites[0].width == 0.5)
    }

    // MARK: - Back-conversion: layer with no matching design rule

    @Test func backConversionNoRule() {
        let lib = IRTechLibrary(
            layers: [
                IRTechLayerDef(name: "M3", type: .routing, direction: .vertical)
            ]
        )

        let doc = LEFTechIRConverter.toLEFDocument(lib)

        #expect(doc.layers.count == 1)
        #expect(doc.layers[0].name == "M3")
        #expect(doc.layers[0].direction == .vertical)
        #expect(doc.layers[0].minwidth == nil)
        #expect(doc.layers[0].spacing == nil)
    }

    // MARK: - Back-conversion: layer with nil direction

    @Test func backConversionNilDirection() {
        let lib = IRTechLibrary(
            layers: [
                IRTechLayerDef(name: "POLY", type: .masterslice)
            ]
        )

        let doc = LEFTechIRConverter.toLEFDocument(lib)
        #expect(doc.layers[0].direction == nil)
    }

    // MARK: - Via back-conversion with nil fields

    @Test func viaBackConversionNilFields() {
        let lib = IRTechLibrary(
            vias: [
                IRTechViaDef(name: "V1", cutLayerName: "C", topLayerName: "T", bottomLayerName: "B")
            ]
        )

        let doc = LEFTechIRConverter.toLEFDocument(lib)
        #expect(doc.vias[0].cutSize == nil)
        #expect(doc.vias[0].cutSpacing == nil)
        #expect(doc.vias[0].enclosure == nil)
    }

    // MARK: - Site back-conversion with PAD class

    @Test func siteBackConversionPad() {
        let lib = IRTechLibrary(
            sites: [
                IRTechSiteDef(name: "PAD_SITE", siteClass: .pad, symmetry: [.x, .r90])
            ]
        )

        let doc = LEFTechIRConverter.toLEFDocument(lib)
        #expect(doc.sites[0].siteClass == .pad)
        #expect(doc.sites[0].symmetry.count == 2)
    }
}
