import Foundation
import LayoutIR
import Testing
@testable import DEF

@Suite("DEF explicit routed PEX source", .timeLimit(.minutes(1)))
struct DEFStrictSourceTests {
    private func source(units: String = "UNITS DISTANCE MICRONS 1000 ;", body: String = "") -> Data {
        Data("VERSION 5.8 ; DESIGN top ; \(units) \(body) END DESIGN".utf8)
    }

    private func read(_ data: Data) throws -> DEFSourceDocument {
        try DEFLibraryReader.readForRoutedPEX(data, maximumSourceBytes: data.count)
    }

    @Test func explicitUnitsRetainLiteralAndTokenProvenance() throws {
        let bytes = source(units: "# UNITS DISTANCE MICRONS 10 ;\nUNITS DISTANCE MICRONS 002000 ;")
        let result = try read(bytes)
        #expect(result.document.dbuPerMicron == 2000)
        #expect(result.unitsDeclaration.dbuPerMicron == 2000)
        #expect(result.unitsDeclaration.literal == "002000")
        #expect(result.unitsDeclaration.tokenRange == 6..<11)
        let text = try #require(String(data: bytes, encoding: .utf8))
        #expect(Array(DEFTokenizer.tokenize(text)[result.unitsDeclaration.tokenRange]) ==
                ["UNITS", "DISTANCE", "MICRONS", "002000", ";"])
        #expect(result.document == (try DEFLibraryReader.read(bytes)))
        let explicitHundred = try read(source(units: "UNITS DISTANCE MICRONS 100 ;"))
        #expect(explicitHundred.unitsDeclaration.dbuPerMicron == 100)
    }

    @Test func optionalStandardUnitsDoNotBecomeAnImplicitPEXScale() throws {
        let bytes = source(units: "")
        #expect(try DEFLibraryReader.read(bytes).dbuPerMicron == 1000)
        #expect(throws: DEFError.unsupportedSourceFeature(context: "DEF source", feature: "omitted UNITS DISTANCE MICRONS")) {
            try read(bytes)
        }
        #expect(throws: DEFError.unsupportedSourceFeature(context: "DEF source", feature: "duplicate UNITS")) {
            try read(source(units: "UNITS DISTANCE MICRONS 1000 ; UNITS DISTANCE MICRONS 2000 ;"))
        }
    }

    @Test(arguments: ["0", "-1", "1.5", "NaN", "Inf", "9007199254740993"])
    func invalidUnitsCannotBecomeSuccessfulSourceFacts(_ literal: String) throws {
        #expect(throws: DEFError.invalidNumber(context: "UNITS DISTANCE MICRONS", token: literal)) {
            try read(source(units: "UNITS DISTANCE MICRONS \(literal) ;"))
        }
    }

    @Test func malformedUnitsAndConnectionsRefuseAtomically() throws {
        for declaration in ["UNITS MICRONS 1000 ;", "UNITS DISTANCE MICRONS ;", "UNITS DISTANCE MICRONS 1000 extra ;"] {
            #expect(throws: DEFError.self) { try read(source(units: declaration)) }
        }
        for section in ["NETS", "SPECIALNETS"] {
            for connection in ["( u A extra )", "( u )", "( u A + USE SIGNAL"] {
                #expect(throws: DEFError.self) {
                    try read(source(body: "\(section) 1 ; - n \(connection) ; END \(section)"))
                }
            }
            #expect(throws: DEFError.self) {
                try read(source(body: "\(section) 1 ; - n ( u A ) + USE UNKNOWN ; END \(section)"))
            }
        }
    }

    @Test func exactRoutesConnectionsRolesExtensionsAndViaPoseRemainRepresented() throws {
        let bytes = source(body: """
        NETS 1 ;
        - n ( u A ) ( PIN out ) + USE SIGNAL + SOURCE NETLIST + ESTCAP 2.5
          + ROUTED m1 ( 10 20 0 ) ( 110 * 7 ) V12 FW
          NEW m2 ( 110 20 ) ( * 120 ) + PROPERTY tag "SUBNET VPIN" ;
        END NETS
        SPECIALNETS 1 ;
        - ground ( u VSS ) + USE GROUND + SOURCE DIST
          + ROUTED m1 20 ( 0 0 0 ) ( 100 0 7 ) V12 FN
          NEW m2 20 ( 100 0 ) ( 100 100 ) ;
        END SPECIALNETS
        """)
        let result = try read(bytes)
        #expect(result.document == (try DEFLibraryReader.read(bytes)))
        let net = try #require(result.document.nets.first)
        #expect(net.connections == [.init(componentName: "u", pinName: "A"), .init(componentName: "PIN", pinName: "out")])
        #expect(net.use == .signal && net.routing.count == 2)
        #expect(net.routing[0].points == [.init(x: 10, y: 20), .init(x: 110, y: 20)])
        #expect(net.routing[0].pointExtensions == [0, 7])
        #expect(net.routing[0].viaName == "V12" && net.routing[0].viaOrientation == .fw)
        #expect(net.routing[1].points == [.init(x: 110, y: 20), .init(x: 110, y: 120)])
        let special = try #require(result.document.specialNets.first)
        #expect(special.use == .ground && special.routing.count == 2)
        #expect(special.routing[0].points[0].ext == 0 && special.routing[0].points[1].ext == 7)
        #expect(special.routing[0].points[2].viaName == "V12" && special.routing[0].points[2].viaOrientation == .fn)
    }

    @Test(arguments: ["SUBNET sub ( v B )", "VPIN virtual LAYER m1 ( 0 0 ) ( 10 10 )", "SHIELDNET guard", "UNKNOWN_GEOMETRY ( 0 0 )"])
    func unretainedNetClausesNeverFlattenIntoPEXConnectivity(_ clause: String) throws {
        for section in ["NETS", "SPECIALNETS"] {
            let bytes = source(body: "\(section) 1 ; - n ( u A ) + \(clause) ; END \(section)")
            _ = try DEFLibraryReader.read(bytes)
            let feature = try #require(clause.split(separator: " ").first)
            let context = section == "NETS" ? "NET n" : "SPECIALNET n"
            #expect(throws: DEFError.unsupportedSourceFeature(context: context, feature: String(feature))) { try read(bytes) }
        }
        #expect(throws: DEFError.unsupportedSourceFeature(context: "NETS", feature: "MUSTJOIN")) {
            try read(source(body: "NETS 1 ; - MUSTJOIN ( u A ) ( v B ) ; END NETS"))
        }
    }

    @Test func existingRouteAndPinRefusalsRemainStrict() throws {
        for route in ["+ NONDEFAULTRULE wide", "+ ROUTED m1 MASK 2 ( 0 0 ) ( 100 0 )",
                      "+ ROUTED m1 ( * * ) ( 100 0 )", "+ ROUTED m1 ( 0 0 -1 ) ( 100 0 )"] {
            #expect(throws: DEFError.self) { try read(source(body: "NETS 1 ; - n ( u A ) \(route) ; END NETS")) }
        }
        #expect(throws: DEFError.self) {
            try read(source(body: "PINS 1 ; - p + NET n + PORT + LAYER m1 ( 0 0 ) ( 10 10 ) + PORT ; END PINS"))
        }
    }

    @Test func byteAdmissionAndActualTraversalCancellationReturnNoDocument() throws {
        let bytes = source()
        #expect(throws: DEFError.sourceLimitExceeded(maximumBytes: bytes.count - 1, actualBytes: bytes.count)) {
            try DEFLibraryReader.readForRoutedPEX(bytes, maximumSourceBytes: bytes.count - 1)
        }
        #expect(throws: DEFError.sourceLimitExceeded(maximumBytes: 0, actualBytes: bytes.count)) {
            try DEFLibraryReader.readForRoutedPEX(bytes, maximumSourceBytes: 0)
        }
        #expect(throws: DEFError.invalidEncoding) {
            try DEFLibraryReader.readForRoutedPEX(Data([0xff]), maximumSourceBytes: 1)
        }
        #expect(throws: DEFError.cancelled) {
            try DEFLibraryReader.readForRoutedPEX(bytes, maximumSourceBytes: bytes.count, isCancelled: { true })
        }
        let longBytes = source(body: "#" + String(repeating: "x", count: 5000) + "\n")
        var polls = 0
        #expect(throws: DEFError.cancelled) {
            try DEFLibraryReader.readForRoutedPEX(longBytes, maximumSourceBytes: longBytes.count, isCancelled: {
                polls += 1
                return polls == 3
            })
        }
        #expect(polls == 3)
    }
}
