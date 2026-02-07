import Testing
import Foundation
import LayoutIR
@testable import DEF

@Suite("DEF Bug Fixes")
struct DEFBugFixTests {

    // MARK: - Bug 1: Net routing wildcard handling

    @Test func testNetRoutingYWildcard() throws {
        // ( * 200 ) should reuse previous X
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        NETS 1 ;
          - net1 ( u1 A ) ( u2 Y )
            + ROUTED metal1 ( 100 300 ) ( * 200 ) ;
        END NETS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.nets.count == 1)
        let wire = doc.nets[0].routing[0]
        #expect(wire.points.count == 2)
        #expect(wire.points[0] == IRPoint(x: 100, y: 300))
        // Wildcard X: reuse previous X (100), Y is 200
        #expect(wire.points[1] == IRPoint(x: 100, y: 200))
    }

    @Test func testNetRoutingXWildcard() throws {
        // ( 500 * ) should reuse previous Y
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        NETS 1 ;
          - net1 ( u1 A ) ( u2 Y )
            + ROUTED metal1 ( 100 300 ) ( 500 * ) ;
        END NETS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.nets.count == 1)
        let wire = doc.nets[0].routing[0]
        #expect(wire.points.count == 2)
        #expect(wire.points[0] == IRPoint(x: 100, y: 300))
        // Wildcard Y: X is 500, reuse previous Y (300)
        #expect(wire.points[1] == IRPoint(x: 500, y: 300))
    }

    // MARK: - Bug 2: nil placementStatus round-trip

    @Test func testComponentNilPlacementRoundTrip() throws {
        let doc = DEFDocument(
            designName: "test",
            dbuPerMicron: 1000,
            components: [
                DEFComponent(name: "u1", macro: "INV", placementStatus: nil)
            ]
        )
        let data = try DEFLibraryWriter.write(doc)
        let text = String(data: data, encoding: .utf8)!
        // Verify no PLACED is written when status is nil
        #expect(!text.contains("PLACED"))
        #expect(!text.contains("FIXED"))
        #expect(!text.contains("UNPLACED"))

        // Round-trip: re-read should still have nil placementStatus
        let result = try DEFLibraryReader.read(data)
        #expect(result.components.count == 1)
        #expect(result.components[0].placementStatus == nil)
    }

    @Test func testPinNilPlacementRoundTrip() throws {
        let doc = DEFDocument(
            designName: "test",
            dbuPerMicron: 1000,
            pins: [
                DEFPin(name: "clk", netName: "clk", placementStatus: nil)
            ]
        )
        let data = try DEFLibraryWriter.write(doc)
        let text = String(data: data, encoding: .utf8)!
        // Verify no PLACED is written when status is nil
        #expect(!text.contains("PLACED"))

        let result = try DEFLibraryReader.read(data)
        #expect(result.pins.count == 1)
        #expect(result.pins[0].placementStatus == nil)
    }

    // MARK: - Bug 3: Duplicate LAYER for pins

    @Test func testPinLayerNoDuplicate() throws {
        let pin = DEFPin(
            name: "data",
            netName: "data",
            layerName: "metal1",
            placementStatus: .placed,
            layerRects: [
                DEFPinLayerRect(layerName: "metal1", rects: [
                    DEFRect(x1: -25, y1: -25, x2: 25, y2: 25)
                ])
            ]
        )
        let doc = DEFDocument(designName: "test", dbuPerMicron: 1000, pins: [pin])
        let data = try DEFLibraryWriter.write(doc)
        let text = String(data: data, encoding: .utf8)!

        // Count occurrences of "+ LAYER" in the pin line
        let pinLines = text.components(separatedBy: "\n").filter { $0.contains("- data") }
        #expect(pinLines.count == 1)
        let pinLine = pinLines[0]
        let layerCount = pinLine.components(separatedBy: "+ LAYER").count - 1
        // Should have exactly 1 LAYER reference, not 2
        #expect(layerCount == 1)
    }

    // MARK: - Bug 5: Net routing NEW continuation segments

    @Test func testDEFNetRoutingNEW() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        NETS 1 ;
          - net1 ( u1 A ) ( u2 Y )
            + ROUTED metal1 ( 0 0 ) ( 100 0 ) via1
            + NEW metal2 ( 100 0 ) ( 100 200 ) ;
        END NETS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.nets.count == 1)
        let net = doc.nets[0]
        #expect(net.routing.count == 2)
        // First segment: ROUTED metal1
        #expect(net.routing[0].status == .routed)
        #expect(net.routing[0].layerName == "metal1")
        #expect(net.routing[0].points.count == 2)
        #expect(net.routing[0].viaName == "via1")
        // Second segment: NEW metal2
        #expect(net.routing[1].status == .new_)
        #expect(net.routing[1].layerName == "metal2")
        #expect(net.routing[1].points.count == 2)
        #expect(net.routing[1].points[0] == IRPoint(x: 100, y: 0))
        #expect(net.routing[1].points[1] == IRPoint(x: 100, y: 200))
    }

    // MARK: - Bug 6: PROPERTYDEFINITIONS with RANGE

    @Test func testDEFPropertyDefinitionsRange() throws {
        let def = """
        VERSION 5.8 ;
        DESIGN test ;
        PROPERTYDEFINITIONS
          COMPONENT weight REAL RANGE 0.0 100.0 ;
          NET priority INTEGER ;
        END PROPERTYDEFINITIONS
        END DESIGN
        """
        let doc = try DEFLibraryReader.read(Data(def.utf8))
        #expect(doc.propertyDefinitions.count == 2)
        // First definition with RANGE should parse correctly
        #expect(doc.propertyDefinitions[0].objectType == "COMPONENT")
        #expect(doc.propertyDefinitions[0].propName == "weight")
        #expect(doc.propertyDefinitions[0].propType == "REAL")
        // Second definition should not be corrupted by RANGE tokens
        #expect(doc.propertyDefinitions[1].objectType == "NET")
        #expect(doc.propertyDefinitions[1].propName == "priority")
        #expect(doc.propertyDefinitions[1].propType == "INTEGER")
    }

    // MARK: - Bug 7: Document-level PROPERTY round-trip

    @Test func testDEFDocumentPropertyRoundTrip() throws {
        var doc = DEFDocument(designName: "test", dbuPerMicron: 1000)
        doc.properties = [
            DEFProperty(key: "author", value: "test_user"),
            DEFProperty(key: "revision", value: "3")
        ]
        let data = try DEFLibraryWriter.write(doc)
        let text = String(data: data, encoding: .utf8)!
        // Writer should output PROPERTY lines
        #expect(text.contains("PROPERTY author test_user ;"))
        #expect(text.contains("PROPERTY revision 3 ;"))

        // Read back and verify properties are preserved
        let result = try DEFLibraryReader.read(data)
        #expect(result.properties.count == 2)
        #expect(result.properties[0].key == "author")
        #expect(result.properties[0].value == "test_user")
        #expect(result.properties[1].key == "revision")
        #expect(result.properties[1].value == "3")
    }

    // MARK: - Bug 4 (original numbering): Special net route point ext round-trip

    @Test func testSpecialNetRoutePointExt() throws {
        let snet = DEFSpecialNet(
            name: "VDD",
            use: .power,
            routing: [
                DEFRouteSegment(
                    status: .routed,
                    layerName: "metal1",
                    width: 200,
                    points: [
                        DEFRoutePoint(x: 0, y: 0, ext: 100),
                        DEFRoutePoint(x: 1000, y: 0, ext: 50)
                    ]
                )
            ]
        )
        let doc = DEFDocument(designName: "test", dbuPerMicron: 1000, specialNets: [snet])
        let data = try DEFLibraryWriter.write(doc)
        let text = String(data: data, encoding: .utf8)!

        // Verify ext values appear in written output
        #expect(text.contains("( 0 0 100 )"))
        #expect(text.contains("( 1000 0 50 )"))

        // Round-trip: read back and verify ext is preserved
        let result = try DEFLibraryReader.read(data)
        #expect(result.specialNets.count == 1)
        let seg = result.specialNets[0].routing[0]
        #expect(seg.points.count == 2)
        #expect(seg.points[0].ext == 100)
        #expect(seg.points[1].ext == 50)
    }
}
