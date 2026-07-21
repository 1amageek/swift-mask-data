import Testing
import Foundation
@testable import LEF
@testable import TechIR

@Suite("LEFTechIRConverter")
struct LEFTechIRConverterTests {

    private func sampleLEFDocument() -> LEFDocument {
        LEFDocument(
            version: "5.8",
            dbuPerMicron: 2000,
            layers: [
                LEFLayerDef(
                    name: "POLY",
                    type: .masterslice
                ),
                LEFLayerDef(
                    name: "M1",
                    type: .routing,
                    direction: .horizontal,
                    pitch: 0.28,
                    width: 0.14,
                    spacing: 0.14,
                    resistance: 0.38,
                    capacitance: 0.22,
                    thickness: 0.36,
                    minwidth: 0.12,
                    area: 0.058
                ),
                LEFLayerDef(
                    name: "VIA1",
                    type: .cut,
                    spacing: 0.17,
                    enclosure: LEFEnclosure(overhang1: 0.05, overhang2: 0.08)
                ),
                LEFLayerDef(
                    name: "M2",
                    type: .routing,
                    direction: .vertical,
                    pitch: 0.28,
                    width: 0.14,
                    spacing: 0.14
                ),
            ],
            vias: [
                LEFViaDef(
                    name: "VIA1_DEFAULT",
                    layers: [
                        LEFViaDef.LEFViaLayer(
                            layerName: "M1",
                            rects: [LEFRect(x1: -0.07, y1: -0.07, x2: 0.07, y2: 0.07)]
                        ),
                        LEFViaDef.LEFViaLayer(
                            layerName: "VIA1",
                            rects: [LEFRect(x1: -0.05, y1: -0.05, x2: 0.05, y2: 0.05)]
                        ),
                        LEFViaDef.LEFViaLayer(
                            layerName: "M2",
                            rects: [LEFRect(x1: -0.07, y1: -0.07, x2: 0.07, y2: 0.07)]
                        ),
                    ]
                )
            ],
            sites: [
                LEFSiteDef(name: "core_site", siteClass: .core, symmetry: [.y], width: 0.19, height: 1.4)
            ]
        )
    }

    @Test func toIRTechLibrary() throws {
        let doc = sampleLEFDocument()
        let lib = try LEFTechIRConverter.toIRTechLibrary(doc)

        #expect(lib.dbuPerMicron == 2000)
        #expect(lib.metadata["lef.version"] == "5.8")

        // Layers
        #expect(lib.layers.count == 4)
        #expect(lib.layers[0].name == "POLY")
        #expect(lib.layers[0].type == .masterslice)
        #expect(lib.layers[1].name == "M1")
        #expect(lib.layers[1].type == .routing)
        #expect(lib.layers[1].direction == .horizontal)
        #expect(lib.layers[1].pitch == 0.28)
        #expect(lib.layers[1].width == 0.14)
        #expect(lib.layers[1].resistance == 0.38)
        #expect(lib.layers[2].name == "VIA1")
        #expect(lib.layers[2].type == .cut)
        #expect(lib.layers[3].direction == .vertical)

        // Design rules
        let m1Rule = lib.designRules.first { $0.layerName == "M1" }
        #expect(m1Rule != nil)
        #expect(m1Rule?.minWidth == 0.12)
        #expect(m1Rule?.minSpacing == 0.14)
        #expect(m1Rule?.minArea == 0.058)

        // Enclosure rules from CUT layers
        let encRules = lib.enclosureRules
        #expect(encRules.count == 1)
        #expect(encRules[0].outerLayerName == "VIA1")
        #expect(encRules[0].minEnclosure == 0.05)

        // Vias
        #expect(lib.vias.count == 1)
        #expect(lib.vias[0].name == "VIA1_DEFAULT")
        #expect(lib.vias[0].bottomLayerName == "M1")
        #expect(lib.vias[0].cutLayerName == "VIA1")
        #expect(lib.vias[0].topLayerName == "M2")
        #expect(lib.vias[0].layers.count == 3)

        // Sites
        #expect(lib.sites.count == 1)
        #expect(lib.sites[0].name == "core_site")
        #expect(lib.sites[0].siteClass == .core)
        #expect(lib.sites[0].width == 0.19)
        #expect(lib.sites[0].height == 1.4)
        #expect(lib.sites[0].symmetry == [.y])
    }

    @Test func roundTrip() throws {
        let original = sampleLEFDocument()
        let lib = try LEFTechIRConverter.toIRTechLibrary(original)
        let reconstructed = LEFTechIRConverter.toLEFDocument(lib)

        #expect(reconstructed.version == "5.8")
        #expect(reconstructed.dbuPerMicron == 2000)
        #expect(reconstructed.layers.count == 4)
        #expect(reconstructed.layers[1].name == "M1")
        #expect(reconstructed.layers[1].type == .routing)
        #expect(reconstructed.layers[1].direction == .horizontal)
        #expect(reconstructed.layers[1].pitch == 0.28)
        #expect(reconstructed.vias.count == 1)
        #expect(reconstructed.vias[0].name == "VIA1_DEFAULT")
        #expect(reconstructed.sites.count == 1)
        #expect(reconstructed.sites[0].siteClass == .core)
    }

    @Test func emptyDocument() throws {
        let doc = LEFDocument()
        let lib = try LEFTechIRConverter.toIRTechLibrary(doc)

        #expect(lib.layers.isEmpty)
        #expect(lib.vias.isEmpty)
        #expect(lib.sites.isEmpty)
        #expect(lib.designRules.isEmpty)
        #expect(lib.dbuPerMicron == 1000)
    }

    @Test func viaWithTwoLayers() throws {
        let doc = LEFDocument(
            vias: [
                LEFViaDef(
                    name: "V_TWO",
                    layers: [
                        LEFViaDef.LEFViaLayer(layerName: "M1", rects: []),
                        LEFViaDef.LEFViaLayer(layerName: "M2", rects: []),
                    ]
                )
            ]
        )
        let lib = try LEFTechIRConverter.toIRTechLibrary(doc)

        #expect(lib.vias[0].bottomLayerName == "M1")
        #expect(lib.vias[0].topLayerName == "M2")
        #expect(lib.vias[0].cutLayerName == "")
    }
}
