import Testing
import Foundation
import LayoutIR
@testable import DEF

@Suite("DEFDocument Codable")
struct DEFDocumentCodableTests {

    @Test func emptyDocumentRoundTrip() throws {
        let original = DEFDocument(designName: "empty")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DEFDocument.self, from: data)
        #expect(decoded == original)
        #expect(decoded.dieArea == nil)
    }

    @Test func fullDocumentRoundTrip() throws {
        let original = DEFDocument(
            version: "5.8",
            designName: "testchip",
            dbuPerMicron: 2000,
            dieArea: DEFDieArea(x1: -100, y1: -200, x2: 50000, y2: 30000),
            components: [
                DEFComponent(name: "u1", macro: "INV", x: 1000, y: 2000, orientation: .n),
                DEFComponent(name: "u2", macro: "BUF", x: 5000, y: 3000, orientation: .fs),
            ],
            pins: [
                DEFPin(name: "clk", direction: .input, netName: "clk", x: 0, y: 500, orientation: .n),
            ],
            nets: [
                DEFNet(name: "n1", connections: [
                    DEFConnection(componentName: "u1", pinName: "Y"),
                    DEFConnection(componentName: "u2", pinName: "A"),
                ]),
            ],
            specialNets: [
                DEFSpecialNet(name: "VDD", use: .power),
            ]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DEFDocument.self, from: data)
        #expect(decoded == original)
        let bb = decoded.dieArea?.boundingBox
        #expect(bb?.x1 == -100)
        #expect(bb?.y1 == -200)
        #expect(bb?.x2 == 50000)
        #expect(bb?.y2 == 30000)
    }

    @Test func nilDieAreaDecodesCorrectly() throws {
        let original = DEFDocument(designName: "nodiearea", dieArea: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DEFDocument.self, from: data)
        #expect(decoded.dieArea == nil)
    }

    @Test func componentCodable() throws {
        let original = DEFComponent(name: "u1", macro: "NAND2", x: -500, y: 300, orientation: .fe)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DEFComponent.self, from: data)
        #expect(decoded == original)
    }

    @Test func pinCodable() throws {
        let original = DEFPin(
            name: "data", direction: .output, netName: "data",
            layerName: "metal1", x: 100, y: 200, orientation: .s
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DEFPin.self, from: data)
        #expect(decoded == original)
    }

    @Test func netCodable() throws {
        let original = DEFNet(name: "clk", connections: [
            DEFConnection(componentName: "u1", pinName: "CK"),
            DEFConnection(componentName: "PIN", pinName: "clk"),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DEFNet.self, from: data)
        #expect(decoded == original)
    }

    @Test func specialNetCodable() throws {
        let original = DEFSpecialNet(
            name: "VSS",
            use: .ground,
            routing: [DEFRouteSegment(layerName: "metal1", width: 200, points: [
                IRPoint(x: 0, y: 0), IRPoint(x: 1000, y: 0),
            ])]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DEFSpecialNet.self, from: data)
        #expect(decoded == original)
    }
}
