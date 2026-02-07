import Testing
import Foundation
import LayoutIR
@testable import CIF

@Suite("CIF Tokenizer Edge Cases")
struct CIFTokenizerEdgeCaseTests {

    @Test func nestedComments() {
        let tokens = CIFTokenizer.tokenize("(outer (inner) outer) L 1;")
        #expect(tokens.count == 1)
        #expect(tokens[0] == "L 1")
    }

    @Test func unmatchedOpenComment() {
        // Unmatched '(' should swallow everything after it
        let tokens = CIFTokenizer.tokenize("L 1; (unmatched B 100;")
        #expect(tokens.count == 1)
        #expect(tokens[0] == "L 1")
    }

    @Test func extraWhitespace() {
        let tokens = CIFTokenizer.tokenize("  DS   1   100  ;  ")
        #expect(tokens.count == 1)
        #expect(tokens[0] == "DS   1   100")
    }

    @Test func consecutiveSemicolons() {
        let tokens = CIFTokenizer.tokenize(";;;")
        #expect(tokens.isEmpty)
    }

    @Test func noSemicolonAtEnd() {
        // Command without trailing semicolon
        let tokens = CIFTokenizer.tokenize("L 1")
        #expect(tokens.count == 1)
        #expect(tokens[0] == "L 1")
    }
}

@Suite("CIF Reader Edge Cases")
struct CIFReaderEdgeCaseTests {

    @Test func invalidEncoding() throws {
        let data = Data([0xFF, 0xFE, 0x00, 0x01]) // Invalid UTF-8
        do {
            _ = try CIFLibraryReader.read(data)
            Issue.record("Should have thrown invalidEncoding")
        } catch let error as CIFError {
            #expect(error == .invalidEncoding)
        }
    }

    @Test func unterminatedCell() throws {
        // DS without matching DF
        let cif = "DS 1 1; L 1; B 100 50 50 25"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        // Should still produce a cell (unterminated is handled gracefully)
        #expect(lib.cells.count == 1)
        #expect(lib.cells[0].elements.count == 1)
    }

    @Test func scaleFactorZero() throws {
        // DS n 0 → division by zero guard
        let cif = "DS 1 0; L 1; B 100 50 50 25; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        #expect(lib.cells.count == 1)
        // Scale should default to 1.0 when denominator is 0
    }

    @Test func boxWithZeroDimension() throws {
        // B with zero length → degenerate rectangle (line)
        let cif = "DS 1 1; L 1; B 0 100 50 50; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        if case .boundary(let b) = lib.cells[0].elements[0] {
            // Half-length of 0 → x range collapsed
            #expect(b.points[0].x == b.points[1].x)
        } else {
            Issue.record("Expected boundary")
        }
    }

    @Test func polygonTwoPoints() throws {
        // P with only 2 points → not enough for polygon, should be skipped
        let cif = "DS 1 1; L 1; P 0 0 100 0; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        // 2 coordinate pairs → 2 points, minimum 3 required
        #expect(lib.cells[0].elements.isEmpty)
    }

    @Test func wireSinglePoint() throws {
        // W with only one point → too few, should be skipped
        let cif = "DS 1 1; L 1; W 10 50 50; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        #expect(lib.cells[0].elements.isEmpty)
    }

    @Test func cellRefWithoutTransform() throws {
        let cif = "DS 2 1; L 1; B 100 100 50 50; DF; DS 1 1; C 2; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        let parent = lib.cells[1]
        if case .cellRef(let ref) = parent.elements[0] {
            #expect(ref.origin == IRPoint(x: 0, y: 0))
            #expect(ref.transform == .identity)
        } else {
            Issue.record("Expected cellRef")
        }
    }

    @Test func multipleCellDefinitions() throws {
        let cif = """
        DS 1 1; L 1; B 100 100 50 50; DF;
        DS 2 1; L 2; W 10 0 0 200 0; DF;
        DS 3 1; C 1 T 0 0; C 2 T 100 0; DF;
        E
        """
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        #expect(lib.cells.count == 3)
        #expect(lib.cells[0].name == "CELL_1")
        #expect(lib.cells[1].name == "CELL_2")
        #expect(lib.cells[2].name == "CELL_3")
    }

    @Test func textLabelAtNegativeCoords() throws {
        let cif = "DS 1 1; L 1; 9 VDD -100 -200; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        if case .text(let t) = lib.cells[0].elements[0] {
            #expect(t.string == "VDD")
            #expect(t.position == IRPoint(x: -100, y: -200))
        } else {
            Issue.record("Expected text")
        }
    }

    @Test func nonIntegerScaleFactor() throws {
        // DS 1 3 → scale = 1/3
        let cif = "DS 1 3; L 1; B 300 300 150 150; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        if case .boundary(let b) = lib.cells[0].elements[0] {
            // B 300 300 150 150 scaled by 1/3
            // length=100, width=100, cx=50, cy=50
            #expect(b.points[0] == IRPoint(x: 0, y: 0))
            #expect(b.points[2] == IRPoint(x: 100, y: 100))
        } else {
            Issue.record("Expected boundary")
        }
    }

    @Test func dataAfterEnd() throws {
        // Data after E should be ignored
        let cif = "DS 1 1; L 1; B 100 100 50 50; DF; E; DS 2 1; DF;"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        // Only cell from before E
        #expect(lib.cells.count == 1)
    }
}
