import Testing
import Foundation
import LayoutIR
@testable import FormatDetector

@Suite("FormatDetector Edge Cases")
struct FormatDetectorEdgeCaseTests {

    @Test func emptyData() {
        #expect(FormatDetector.detect(Data()) == .unknown)
    }

    @Test func tooShortData() {
        #expect(FormatDetector.detect(Data([0x00])) == .unknown)
        #expect(FormatDetector.detect(Data([0x00, 0x06])) == .unknown)
        #expect(FormatDetector.detect(Data([0x00, 0x06, 0x00])) == .unknown)
    }

    @Test func truncatedOASISMagic() {
        // Partial OASIS magic should not match
        let partial = Data("%SEMI-OASI".utf8)
        #expect(FormatDetector.detect(partial) != .oasis)
    }

    @Test func gdsiiLikeButNot() {
        // Bytes [2..3] == 0x00 0x02 but first two bytes are wrong for GDSII
        // Still detected as GDSII since we only check record type bytes
        let data = Data([0xFF, 0xFF, 0x00, 0x02, 0x00, 0x00])
        #expect(FormatDetector.detect(data) == .gdsii)
    }

    @Test func cifWithLeadingWhitespace() {
        let text = "   \n\n  DS 1 1; E\n"
        #expect(FormatDetector.detect(Data(text.utf8)) == .cif)
    }

    @Test func cifStartingWithE() {
        // "E\n" is only 2 bytes, below the 4-byte minimum for detection
        let text = "E\n"
        #expect(FormatDetector.detect(Data(text.utf8)) == .unknown)
        // Padded version should detect as CIF
        let padded = "E   \n"
        #expect(FormatDetector.detect(Data(padded.utf8)) == .cif)
    }

    @Test func lefWithoutMacro() {
        // LEF with LAYER but no MACRO
        let text = "VERSION 5.8 ;\nLAYER metal1\n  TYPE ROUTING ;\nEND metal1\n"
        #expect(FormatDetector.detect(Data(text.utf8)) == .lef)
    }

    @Test func defWithoutDesignNearby() {
        // Has VERSION but also has DESIGN
        let text = "VERSION 5.8 ;\nBUSBITCHARS \"[]\" ;\nDESIGN chip ;\n"
        #expect(FormatDetector.detect(Data(text.utf8)) == .def)
    }

    @Test func ambiguousVersionOnly() {
        // Just "VERSION" without DESIGN/LAYER/MACRO could be LEF or DEF
        // Our detector needs both keywords
        let text = "VERSION 5.8 ;\n"
        let result = FormatDetector.detect(Data(text.utf8))
        // Should not falsely match LEF or DEF
        #expect(result != .lef)
        #expect(result != .def)
    }

    @Test func dxfWithLeadingSpaces() {
        let text = "  0\nSECTION\n  2\nENTITIES\n  0\nENDSEC\n  0\nEOF\n"
        #expect(FormatDetector.detect(Data(text.utf8)) == .dxf)
    }

    @Test func binaryGarbageNotMatchingAnything() {
        let data = Data(repeating: 0xAB, count: 1000)
        #expect(FormatDetector.detect(data) == .unknown)
    }

    @Test func cifWithNestedComments() {
        let text = "(outer (inner comment) still outer) DS 1 1; E\n"
        #expect(FormatDetector.detect(Data(text.utf8)) == .cif)
    }

    @Test func nullBytesInData() {
        let data = Data(repeating: 0x00, count: 100)
        #expect(FormatDetector.detect(data) != .cif)
    }
}
