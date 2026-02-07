import Testing
import Foundation
@testable import TechIR

@Suite("TechIR Edge Cases")
struct TechIREdgeCaseTests {

    // MARK: - IRTechLayerDef with all optionals nil

    @Test func layerDefAllNils() throws {
        let layer = IRTechLayerDef(name: "BARE", type: .implant)
        #expect(layer.gdsLayer == nil)
        #expect(layer.gdsDatatype == nil)
        #expect(layer.direction == nil)
        #expect(layer.pitch == nil)
        #expect(layer.width == nil)
        #expect(layer.spacing == nil)
        #expect(layer.color == nil)
        #expect(layer.fillPattern == nil)
        #expect(layer.visibleByDefault == nil)
        #expect(layer.spacingTable == nil)
        #expect(layer.minArea == nil)

        let data = try JSONEncoder().encode(layer)
        let decoded = try JSONDecoder().decode(IRTechLayerDef.self, from: data)
        #expect(decoded == layer)
    }

    // MARK: - IRTechViaDef with all optionals nil

    @Test func viaDefAllNils() throws {
        let via = IRTechViaDef(name: "V", cutLayerName: "C", topLayerName: "T", bottomLayerName: "B")
        #expect(via.cutWidth == nil)
        #expect(via.cutHeight == nil)
        #expect(via.enclosure == nil)
        #expect(via.spacing == nil)
        #expect(via.resistance == nil)
        #expect(via.layers.isEmpty)

        let data = try JSONEncoder().encode(via)
        let decoded = try JSONDecoder().decode(IRTechViaDef.self, from: data)
        #expect(decoded == via)
    }

    // MARK: - IRTechLibrary with extreme dbuPerMicron

    @Test func extremeDBUValues() throws {
        let lib1 = IRTechLibrary(dbuPerMicron: 1)
        let lib2 = IRTechLibrary(dbuPerMicron: 100000)

        let data1 = try JSONEncoder().encode(lib1)
        let data2 = try JSONEncoder().encode(lib2)
        let decoded1 = try JSONDecoder().decode(IRTechLibrary.self, from: data1)
        let decoded2 = try JSONDecoder().decode(IRTechLibrary.self, from: data2)
        #expect(decoded1.dbuPerMicron == 1)
        #expect(decoded2.dbuPerMicron == 100000)
    }

    // MARK: - IRTechColor alpha channel

    @Test func colorAlphaDefault() {
        let color = IRTechColor(red: 1.0, green: 0.0, blue: 0.0)
        #expect(color.alpha == 1.0)
    }

    @Test func colorFullyTransparent() throws {
        let color = IRTechColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.0)
        let data = try JSONEncoder().encode(color)
        let decoded = try JSONDecoder().decode(IRTechColor.self, from: data)
        #expect(decoded.alpha == 0.0)
    }

    // MARK: - IRTechSymmetry

    @Test func symmetryArray() throws {
        let site = IRTechSiteDef(name: "S", symmetry: [.x, .y, .r90])
        let data = try JSONEncoder().encode(site)
        let decoded = try JSONDecoder().decode(IRTechSiteDef.self, from: data)
        #expect(decoded.symmetry == [.x, .y, .r90])
    }

    @Test func emptySymmetry() throws {
        let site = IRTechSiteDef(name: "S")
        #expect(site.symmetry.isEmpty)
        let data = try JSONEncoder().encode(site)
        let decoded = try JSONDecoder().decode(IRTechSiteDef.self, from: data)
        #expect(decoded.symmetry.isEmpty)
    }

    // MARK: - IRTechDesignRule with partial nils

    @Test func designRulePartialNils() throws {
        let rule = IRTechDesignRule(layerName: "M1", minWidth: 0.14)
        #expect(rule.minSpacing == nil)
        #expect(rule.minArea == nil)
        #expect(rule.minDensity == nil)
        #expect(rule.maxDensity == nil)

        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(IRTechDesignRule.self, from: data)
        #expect(decoded == rule)
    }

    // MARK: - ViaLayerGeometry with empty rects

    @Test func viaLayerEmptyRects() throws {
        let geo = IRTechViaLayerGeometry(layerName: "M1")
        #expect(geo.rects.isEmpty)

        let data = try JSONEncoder().encode(geo)
        let decoded = try JSONDecoder().decode(IRTechViaLayerGeometry.self, from: data)
        #expect(decoded.rects.isEmpty)
    }

    // MARK: - SpacingTable empty entries

    @Test func spacingTableEmpty() throws {
        let table = IRTechSpacingTable(entries: [])
        let data = try JSONEncoder().encode(table)
        let decoded = try JSONDecoder().decode(IRTechSpacingTable.self, from: data)
        #expect(decoded.entries.isEmpty)
    }
}
