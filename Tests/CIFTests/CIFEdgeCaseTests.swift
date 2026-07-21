import Testing
import Foundation
import LayoutIR
@testable import CIF

@Suite("CIF Tokenizer Edge Cases")
struct CIFTokenizerEdgeCaseTests {

    @Test func nestedComments() throws {
        let tokens = try CIFTokenizer.tokenize("(outer (inner) outer) L 1;")
        #expect(tokens.count == 1)
        #expect(tokens[0] == "L 1")
    }

    @Test func unmatchedOpenComment() {
        #expect(throws: CIFError.unterminatedComment) {
            _ = try CIFTokenizer.tokenize("L 1; (unmatched B 100;")
        }
    }

    @Test func extraWhitespace() throws {
        let tokens = try CIFTokenizer.tokenize("  DS   1   100  ;  ")
        #expect(tokens.count == 1)
        #expect(tokens[0] == "DS   1   100")
    }

    @Test func consecutiveSemicolons() throws {
        let tokens = try CIFTokenizer.tokenize(";;;")
        #expect(tokens.isEmpty)
    }

    @Test func noSemicolonAtEnd() {
        #expect(throws: CIFError.unterminatedCommand("L 1")) {
            _ = try CIFTokenizer.tokenize("L 1")
        }
    }
}

@Suite("CIF Reader Edge Cases")
struct CIFReaderEdgeCaseTests {

    @Test func invalidEncoding() throws {
        let data = Data([0xFF, 0xFE, 0x00, 0x01]) // Invalid UTF-8
        do {
            _ = try CIFLibraryReader.read(data, databaseUnitScale: try testDatabaseUnitScale())
            Issue.record("Should have thrown invalidEncoding")
        } catch let error as CIFError {
            #expect(error == .invalidEncoding)
        }
    }

    @Test func unterminatedCell() throws {
        let cif = "DS 1 1; L 1; B 100 50 50 25; E"
        #expect(throws: CIFError.unterminatedCell("CELL_1")) {
            _ = try CIFLibraryReader.read(Data(cif.utf8), databaseUnitScale: try testDatabaseUnitScale())
        }
    }

    @Test func missingEndCommand() throws {
        let cif = "DS 1 1; L 1; B 100 50 50 25; DF;"
        #expect(throws: CIFError.missingEndCommand) {
            _ = try CIFLibraryReader.read(Data(cif.utf8), databaseUnitScale: try testDatabaseUnitScale())
        }
    }

    @Test func scaleFactorZero() throws {
        let cif = "DS 1 0; L 1; B 100 50 50 25; DF; E"
        #expect(throws: CIFError.invalidCommand(command: "DS 1 0", reason: "scale denominator is zero")) {
            _ = try CIFLibraryReader.read(Data(cif.utf8), databaseUnitScale: try testDatabaseUnitScale())
        }
    }

    @Test func boxWithZeroDimension() throws {
        let cif = "DS 1 1; L 1; B 0 100 50 50; DF; E"
        #expect(throws: CIFError.invalidCommand(command: "B 0 100 50 50", reason: "box dimensions must be positive")) {
            _ = try CIFLibraryReader.read(Data(cif.utf8), databaseUnitScale: try testDatabaseUnitScale())
        }
    }

    @Test func polygonTwoPoints() throws {
        let cif = "DS 1 1; L 1; P 0 0 100 0; DF; E"
        #expect(throws: CIFError.invalidCommand(command: "P 0 0 100 0", reason: "P requires at least three coordinate pairs")) {
            _ = try CIFLibraryReader.read(Data(cif.utf8), databaseUnitScale: try testDatabaseUnitScale())
        }
    }

    @Test func wireSinglePoint() throws {
        let cif = "DS 1 1; L 1; W 10 50 50; DF; E"
        #expect(throws: CIFError.invalidCommand(command: "W 10 50 50", reason: "W requires a width and at least two coordinate pairs")) {
            _ = try CIFLibraryReader.read(Data(cif.utf8), databaseUnitScale: try testDatabaseUnitScale())
        }
    }

    @Test func cellRefWithoutTransform() throws {
        let cif = "DS 2 1; L 1; B 100 100 50 50; DF; DS 1 1; C 2; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8), databaseUnitScale: try testDatabaseUnitScale())
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
        let lib = try CIFLibraryReader.read(Data(cif.utf8), databaseUnitScale: try testDatabaseUnitScale())
        #expect(lib.cells.count == 3)
        #expect(lib.cells[0].name == "CELL_1")
        #expect(lib.cells[1].name == "CELL_2")
        #expect(lib.cells[2].name == "CELL_3")
    }

    @Test func textLabelAtNegativeCoords() throws {
        let cif = "DS 1 1; L 1; 9 VDD -100 -200; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8), databaseUnitScale: try testDatabaseUnitScale())
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
        let lib = try CIFLibraryReader.read(Data(cif.utf8), databaseUnitScale: try testDatabaseUnitScale())
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
        let cif = "DS 1 1; L 1; B 100 100 50 50; DF; E; DS 2 1; DF;"
        #expect(throws: CIFError.commandAfterEnd("DS 2 1")) {
            _ = try CIFLibraryReader.read(Data(cif.utf8), databaseUnitScale: try testDatabaseUnitScale())
        }
    }

    @Test func duplicateCellNameExtensionIsRejected() throws {
        let cif = "DS 1 1; 9 FIRST; 9 SECOND; DF; E"
        #expect(throws: CIFError.invalidCommand(command: "9 SECOND", reason: "cell name is already defined")) {
            _ = try CIFLibraryReader.read(Data(cif.utf8), databaseUnitScale: try testDatabaseUnitScale())
        }
    }

    @Test func namedLayerDoesNotCollideWithNumericLayer() throws {
        let cif = "DS 1 1; L METAL1; B 10 10 5 5; L 1; B 10 10 25 5; DF; E"
        let library = try CIFLibraryReader.read(
            Data(cif.utf8),
            databaseUnitScale: try testDatabaseUnitScale()
        )

        guard case .boundary(let namedLayerBoundary) = library.cells[0].elements[0],
              case .boundary(let numericLayerBoundary) = library.cells[0].elements[1] else {
            Issue.record("Expected two boundaries")
            return
        }
        #expect(namedLayerBoundary.layer != numericLayerBoundary.layer)
        #expect(numericLayerBoundary.layer == 1)
    }
}
