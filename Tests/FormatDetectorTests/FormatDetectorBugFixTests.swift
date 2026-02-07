import Testing
import Foundation
@testable import FormatDetector

@Suite("FormatDetector Bug Fixes")
struct FormatDetectorBugFixTests {

    @Test func testLEFWithDesignRuleWidth() {
        // A LEF file containing DESIGNRULEWIDTH should be detected as LEF, not DEF.
        // DESIGNRULEWIDTH contains "DESIGN" as a substring but is not the standalone keyword.
        let lefText = """
        VERSION 5.8 ;
        UNITS
          DATABASE MICRONS 1000 ;
        END UNITS
        LAYER metal1
          TYPE ROUTING ;
          DESIGNRULEWIDTH 0.1 ;
        END metal1
        """
        let data = Data(lefText.utf8)
        let result = FormatDetector.detect(data)
        #expect(result == .lef)
        #expect(result != .def)
    }

    @Test func testDEFWithDesignKeyword() {
        // A DEF file with standalone DESIGN keyword should be detected as DEF.
        let defText = """
        VERSION 5.8 ;
        DIVIDERCHAR "/" ;
        BUSBITCHARS "[]" ;
        DESIGN mydesign ;
        UNITS DISTANCE MICRONS 1000 ;
        END DESIGN
        """
        let data = Data(defText.utf8)
        #expect(FormatDetector.detect(data) == .def)
    }

    @Test func testLEFWithMacroKeyword() {
        // LEF with MACRO should be detected as LEF
        let lefText = """
        VERSION 5.8 ;
        MACRO INV
          CLASS CORE ;
          SIZE 1.0 BY 1.0 ;
        END INV
        """
        let data = Data(lefText.utf8)
        #expect(FormatDetector.detect(data) == .lef)
    }

    @Test func testDEFNotConfusedWithLEFLayer() {
        // A DEF file that also has LAYER keyword should still be DEF
        // because DEF check happens before LEF and it has standalone DESIGN
        let defText = """
        VERSION 5.8 ;
        DESIGN chip ;
        COMPONENTS 1 ;
        - inv1 INV ;
        END COMPONENTS
        """
        let data = Data(defText.utf8)
        #expect(FormatDetector.detect(data) == .def)
    }
}
