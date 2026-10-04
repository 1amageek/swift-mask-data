import Foundation
import Testing
@testable import DEF

@Suite("DEF pin parser admission", .timeLimit(.minutes(1)))
struct DEFPinAdmissionTests {
    private func bytes(_ clauses: String) -> Data {
        Data("VERSION 5.8 ; DESIGN top ; UNITS DISTANCE MICRONS 2000 ; PINS 2 ; - GOOD + NET G + LAYER M1 ( 0 0 ) ( 10 20 ) + FIXED ( 100 200 ) N ; - P + NET N \(clauses) ; END PINS END DESIGN".utf8)
    }

    @Test(arguments: [
        "+ POLYGON M2 ( 0 0 ) ( 20 0 ) ( 20 20 ) ( 0 20 )",
        "+ VIA VIA12 ( 0 0 )",
        "+ PORT + LAYER M2 ( 0 0 ) ( 10 20 ) + FIXED ( 300 400 ) S"
    ])
    func unsupportedAdditionalGeometryCannotPublishPartialPins(_ extra: String) throws {
        var output: DEFDocument?
        let feature = extra.hasPrefix("+ PORT") ? "multiple PORTs" : extra.hasPrefix("+ VIA") ? "VIA" : "POLYGON"
        #expect(throws: DEFError.unsupportedPinFeature(pinName: "P", feature: feature)) {
            output = try DEFLibraryReader.read(bytes("+ LAYER M1 ( 0 0 ) ( 10 20 ) + FIXED ( 100 200 ) N \(extra)"))
        }
        #expect(output == nil)
    }

    @Test(arguments: ["+ PLACED ( 100 200 ) BAD", "+ DIRECTION BAD", "+ USE BAD"])
    func unknownEnumValueCannotBecomeDefault(_ clause: String) throws {
        var output: DEFDocument?
        let field = clause.hasPrefix("+ PLACED") ? "orientation" : clause.hasPrefix("+ DIRECTION") ? "DIRECTION" : "USE"
        #expect(throws: DEFError.invalidPinValue(pinName: "P", field: field, token: "BAD")) {
            output = try DEFLibraryReader.read(bytes("+ LAYER M1 ( 0 0 ) ( 10 20 ) \(clause)"))
        }
        #expect(output == nil)
    }

    @Test func singleExplicitRectangularPortPreservesEveryStandardEnumAndPose() throws {
        for (index, orientation) in ["N", "S", "E", "W", "FN", "FS", "FE", "FW"].enumerated() {
            let direction = ["INPUT", "OUTPUT", "INOUT", "FEEDTHRU"][index % 4]
            let use = ["SIGNAL", "POWER", "GROUND", "CLOCK", "TIEOFF", "ANALOG", "SCAN", "RESET"][index]
            let source = try DEFLibraryReader.read(bytes("+ DIRECTION \(direction) + USE \(use) + SPECIAL + PORT + LAYER M1 ( -10 -20 ) ( 30 40 ) + LAYER M2 ( 0 0 ) ( 50 60 ) + FIXED ( -100 200 ) \(orientation)"))
            let pin = try #require(source.pins.last)
            #expect(pin.direction?.rawValue == direction && pin.use?.rawValue == use)
            #expect(pin.orientation.rawValue == orientation && pin.x == -100 && pin.y == 200)
            #expect(pin.placementStatus == .fixed && pin.special && pin.netName == "N")
            #expect(pin.layerRects == [.init(layerName: "M1", rects: [.init(x1: -10, y1: -20, x2: 30, y2: 40)]),
                                      .init(layerName: "M2", rects: [.init(x1: 0, y1: 0, x2: 50, y2: 60)])])
            let roundtrip = try DEFLibraryReader.read(DEFLibraryWriter.write(source))
            #expect(roundtrip.pins == source.pins && roundtrip.dbuPerMicron == 2000)
        }
    }
    @Test(arguments: ["MASK", "SPACING", "DESIGNRULEWIDTH"])
    func validUnrepresentedLayerModifiersAreUnsupported(_ modifier: String) throws {
        var output: DEFDocument?
        #expect(throws: DEFError.unsupportedPinFeature(pinName: "P", feature: modifier)) {
            output = try DEFLibraryReader.read(bytes("+ LAYER M1 ( 0 0 ) ( 10 20 ) + LAYER M2 \(modifier) 1 ( 0 0 ) ( 10 20 )"))
        }
        #expect(output == nil)
    }

    @Test func secondExplicitPortAndUnrepresentedMetadataDoNotDisappear() throws {
        for (clauses, feature) in [
            ("+ PORT + LAYER M1 ( 0 0 ) ( 10 20 ) + FIXED ( 100 200 ) N + PORT + LAYER M2 ( 0 0 ) ( 10 20 ) + FIXED ( 300 400 ) S", "multiple PORTs"),
            ("+ LAYER M1 ( 0 0 ) ( 10 20 ) + NETEXPR \"expr N\"", "NETEXPR"),
            ("+ LAYER M1 ( 0 0 ) ( 10 20 ) + FIXED ( 100 200 ) N + FIXED ( 300 400 ) S", "multiple placements")
        ] {
            #expect(throws: DEFError.unsupportedPinFeature(pinName: "P", feature: feature)) {
                try DEFLibraryReader.read(bytes(clauses))
            }
        }
    }

    @Test func malformedSupportedPointAndMissingOrientationAreInvalid() throws {
        #expect(throws: DEFError.invalidPinSyntax(pinName: "P", expected: ")", token: "+")) {
            try DEFLibraryReader.read(bytes("+ LAYER M1 ( 0 0 + FIXED ( 100 200 ) N"))
        }
        #expect(throws: DEFError.invalidPinSyntax(pinName: "P", expected: "orientation", token: ";")) {
            try DEFLibraryReader.read(bytes("+ LAYER M1 ( 0 0 ) ( 10 20 ) + PLACED ( 100 200 )"))
        }
    }

    @Test func supportedPlacementStatusesAndAbsentEnumsRemainExact() throws {
        for clause in ["+ PLACED ( 100 200 ) W", "+ FIXED ( 100 200 ) FN", "+ COVER ( 100 200 ) FE", "+ UNPLACED", ""] {
            let document = try DEFLibraryReader.read(bytes("+ LAYER M1 ( 0 0 ) ( 10 20 ) \(clause)"))
            let pin = try #require(document.pins.last)
            #expect(pin.direction == nil && pin.use == nil)
            #expect(try DEFLibraryReader.read(DEFLibraryWriter.write(document)).pins == document.pins)
        }
    }

}
