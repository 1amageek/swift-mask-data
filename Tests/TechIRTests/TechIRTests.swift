import Testing
import Foundation
@testable import TechIR

@Suite("IRTechLibrary")
struct IRTechLibraryTests {

    @Test func defaultInit() {
        let lib = IRTechLibrary()
        #expect(lib.name == "")
        #expect(lib.dbuPerMicron == 1000)
        #expect(lib.layers.isEmpty)
        #expect(lib.vias.isEmpty)
        #expect(lib.sites.isEmpty)
        #expect(lib.designRules.isEmpty)
        #expect(lib.enclosureRules.isEmpty)
        #expect(lib.antennaRules.isEmpty)
        #expect(lib.metadata.isEmpty)
    }

    @Test func jsonRoundTrip() throws {
        let lib = IRTechLibrary(
            name: "test_tech",
            dbuPerMicron: 2000,
            layers: [
                IRTechLayerDef(
                    name: "M1",
                    type: .routing,
                    gdsLayer: 10,
                    gdsDatatype: 0,
                    direction: .horizontal,
                    pitch: 0.28,
                    width: 0.14,
                    spacing: 0.14,
                    color: IRTechColor(red: 0.2, green: 0.4, blue: 0.8),
                    fillPattern: .forwardDiagonal,
                    visibleByDefault: true
                ),
                IRTechLayerDef(
                    name: "VIA1",
                    type: .cut,
                    gdsLayer: 11,
                    gdsDatatype: 0,
                    color: IRTechColor(red: 0.5, green: 0.5, blue: 0.5),
                    fillPattern: .crosshatch
                ),
            ],
            vias: [
                IRTechViaDef(
                    name: "VIA1_DEF",
                    cutLayerName: "VIA1",
                    topLayerName: "M2",
                    bottomLayerName: "M1",
                    cutWidth: 0.1,
                    cutHeight: 0.1,
                    enclosure: IRTechEnclosureValues(overhang1: 0.05, overhang2: 0.05),
                    spacing: 0.12,
                    layers: [
                        IRTechViaLayerGeometry(
                            layerName: "M1",
                            rects: [IRTechRect(x1: -0.12, y1: -0.12, x2: 0.12, y2: 0.12)]
                        )
                    ]
                )
            ],
            sites: [
                IRTechSiteDef(name: "core_site", siteClass: .core, width: 0.19, height: 1.4, symmetry: [.y])
            ],
            designRules: [
                IRTechDesignRule(layerName: "M1", minWidth: 0.14, minSpacing: 0.14, minArea: 0.058)
            ],
            enclosureRules: [
                IRTechEnclosureRule(outerLayerName: "M1", innerLayerName: "VIA1", minEnclosure: 0.05)
            ],
            antennaRules: [
                IRTechAntennaRule(layerName: "M1", maxRatio: 400)
            ],
            metadata: ["source": "test"]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(lib)
        let decoded = try JSONDecoder().decode(IRTechLibrary.self, from: data)

        #expect(decoded == lib)
        #expect(decoded.name == "test_tech")
        #expect(decoded.dbuPerMicron == 2000)
        #expect(decoded.layers.count == 2)
        #expect(decoded.layers[0].name == "M1")
        #expect(decoded.layers[0].type == .routing)
        #expect(decoded.layers[0].direction == .horizontal)
        #expect(decoded.layers[1].type == .cut)
        #expect(decoded.vias.count == 1)
        #expect(decoded.vias[0].cutLayerName == "VIA1")
        #expect(decoded.vias[0].layers.count == 1)
        #expect(decoded.sites.count == 1)
        #expect(decoded.sites[0].siteClass == .core)
        #expect(decoded.designRules.count == 1)
        #expect(decoded.enclosureRules.count == 1)
        #expect(decoded.antennaRules.count == 1)
    }

    @Test func decodingRejectsMissingRequiredFields() {
        let data = Data(#"{"name":"broken","layers":[],"vias":[],"sites":[],"designRules":[],"enclosureRules":[],"antennaRules":[],"metadata":{}}"#.utf8)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(IRTechLibrary.self, from: data)
        }
    }

    @Test func decodingRejectsMissingExtensionAndMinimumCutRules() {
        let data = Data(#"{"name":"incomplete","dbuPerMicron":1000,"layers":[],"vias":[],"sites":[],"designRules":[],"enclosureRules":[],"antennaRules":[],"metadata":{}}"#.utf8)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(IRTechLibrary.self, from: data)
        }
    }

    @Test func hashableConformance() {
        let a = IRTechLayerDef(name: "M1", type: .routing, gdsLayer: 10)
        let b = IRTechLayerDef(name: "M1", type: .routing, gdsLayer: 10)
        let c = IRTechLayerDef(name: "M2", type: .routing, gdsLayer: 20)

        #expect(a == b)
        #expect(a != c)

        let set: Set<IRTechLayerDef> = [a, b, c]
        #expect(set.count == 2)
    }
}

@Suite("IRTechLayerType")
struct IRTechLayerTypeTests {

    @Test func allCases() throws {
        let types: [IRTechLayerType] = [.routing, .cut, .masterslice, .overlap, .implant]
        for t in types {
            let data = try JSONEncoder().encode(t)
            let decoded = try JSONDecoder().decode(IRTechLayerType.self, from: data)
            #expect(decoded == t)
        }
    }
}

@Suite("IRTechFillPattern")
struct IRTechFillPatternTests {

    @Test func allCases() throws {
        let patterns: [IRTechFillPattern] = [
            .solid, .forwardDiagonal, .backwardDiagonal, .crosshatch,
            .horizontal, .vertical, .grid, .dots
        ]
        for p in patterns {
            let data = try JSONEncoder().encode(p)
            let decoded = try JSONDecoder().decode(IRTechFillPattern.self, from: data)
            #expect(decoded == p)
        }
    }
}

@Suite("IRTechSpacingTable")
struct IRTechSpacingTableTests {

    @Test func roundTrip() throws {
        let table = IRTechSpacingTable(entries: [
            IRTechSpacingWidthEntry(width: 0.14, spacing: 0.14),
            IRTechSpacingWidthEntry(width: 0.28, spacing: 0.21),
        ])
        let data = try JSONEncoder().encode(table)
        let decoded = try JSONDecoder().decode(IRTechSpacingTable.self, from: data)
        #expect(decoded == table)
        #expect(decoded.entries.count == 2)
    }
}
