import Testing
import Foundation
import LayoutIR
@testable import FormatDetector
@testable import GDSII
@testable import OASIS

@Suite("LayoutFormat")
struct LayoutFormatTests {

    @Test func allCases() {
        let cases = LayoutFormat.allCases
        #expect(cases.count == 7)
        #expect(cases.contains(.gdsii))
        #expect(cases.contains(.oasis))
        #expect(cases.contains(.cif))
        #expect(cases.contains(.dxf))
        #expect(cases.contains(.def))
        #expect(cases.contains(.lef))
        #expect(cases.contains(.unknown))
    }
}

@Suite("FormatDetector")
struct FormatDetectorTests {

    @Test func detectGDSII() {
        // GDSII header: 2 bytes length + record type 0x0002
        var data = Data([0x00, 0x06, 0x00, 0x02, 0x00, 0x07])
        #expect(FormatDetector.detect(data) == .gdsii)
    }

    @Test func detectOASIS() {
        let magic = Data("%SEMI-OASIS\r\n".utf8)
        var data = magic
        data.append(contentsOf: [0x01, 0x00]) // some extra bytes
        #expect(FormatDetector.detect(data) == .oasis)
    }

    @Test func detectCIF() {
        let cifText = "DS 1 100;\nL METAL1;\nB 100 50 50 25;\nDF;\nE\n"
        let data = Data(cifText.utf8)
        #expect(FormatDetector.detect(data) == .cif)
    }

    @Test func detectCIFWithComment() {
        let cifText = "(This is a CIF file)\nDS 1 100;\nE\n"
        let data = Data(cifText.utf8)
        #expect(FormatDetector.detect(data) == .cif)
    }

    @Test func detectDXF() {
        let dxfText = "  0\nSECTION\n  2\nHEADER\n  0\nENDSEC\n  0\nEOF\n"
        let data = Data(dxfText.utf8)
        #expect(FormatDetector.detect(data) == .dxf)
    }

    @Test func detectDEF() {
        let defText = "VERSION 5.8 ;\nDIVIDERCHAR \"/\" ;\nBUSBITCHARS \"[]\" ;\nDESIGN mydesign ;\nUNITS DISTANCE MICRONS 1000 ;\nEND DESIGN\n"
        let data = Data(defText.utf8)
        #expect(FormatDetector.detect(data) == .def)
    }

    @Test func detectLEF() {
        let lefText = "VERSION 5.8 ;\nUNITS\n  DATABASE MICRONS 1000 ;\nEND UNITS\nLAYER metal1\n  TYPE ROUTING ;\nEND metal1\n"
        let data = Data(lefText.utf8)
        #expect(FormatDetector.detect(data) == .lef)
    }

    @Test func unknownData() {
        let data = Data([0xFF, 0xFE, 0xAB, 0xCD, 0x12, 0x34])
        #expect(FormatDetector.detect(data) == .unknown)
    }

    @Test func realGDSII() throws {
        // Build a real GDSII binary from IRLibrary
        let lib = IRLibrary(name: "TEST", units: .default, cells: [IRCell(name: "TOP")])
        let data = try GDSLibraryWriter.write(lib)
        #expect(FormatDetector.detect(data) == .gdsii)
    }

    @Test func realOASIS() throws {
        // Build a real OASIS binary from IRLibrary
        let lib = IRLibrary(name: "TEST", units: .default, cells: [IRCell(name: "TOP")])
        let data = try OASISLibraryWriter.write(lib)
        #expect(FormatDetector.detect(data) == .oasis)
    }
}
