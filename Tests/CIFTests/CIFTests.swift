import Testing
import Foundation
import LayoutIR
@testable import CIF

// MARK: - CIF Tokenizer Tests

@Suite("CIFTokenizer")
struct CIFTokenizerTests {

    @Test func emptyInput() {
        let tokens = CIFTokenizer.tokenize("")
        #expect(tokens.isEmpty)
    }

    @Test func simpleCommand() {
        let tokens = CIFTokenizer.tokenize("L 1;")
        #expect(tokens.count == 1)
        #expect(tokens[0] == "L 1")
    }

    @Test func commentSkipping() {
        let tokens = CIFTokenizer.tokenize("(this is a comment) L 1;")
        #expect(tokens.count == 1)
        #expect(tokens[0] == "L 1")
    }

    @Test func multipleCommands() {
        let tokens = CIFTokenizer.tokenize("DS 1 100; L 1; B 100 50 50 25; DF;")
        #expect(tokens.count == 4)
        #expect(tokens[0] == "DS 1 100")
        #expect(tokens[1] == "L 1")
    }
}

// MARK: - CIF Reader Tests

@Suite("CIFLibraryReader")
struct CIFLibraryReaderTests {

    @Test func emptyFile() throws {
        let data = Data("E".utf8)
        let lib = try CIFLibraryReader.read(data)
        #expect(lib.cells.isEmpty)
    }

    @Test func singleBox() throws {
        let cif = "DS 1 1; L 1; B 100 50 50 25; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        #expect(lib.cells.count == 1)
        #expect(lib.cells[0].name == "CELL_1")
        #expect(lib.cells[0].elements.count == 1)
        if case .boundary(let b) = lib.cells[0].elements[0] {
            #expect(b.layer == 1)
            #expect(b.points.count == 5)
            // B 100 50 50 25 → center(50,25), half-length=50, half-width=25
            #expect(b.points[0] == IRPoint(x: 0, y: 0))
            #expect(b.points[2] == IRPoint(x: 100, y: 50))
        } else {
            Issue.record("Expected boundary element")
        }
    }

    @Test func wire() throws {
        let cif = "DS 1 1; L 2; W 10 0 0 100 0; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        #expect(lib.cells[0].elements.count == 1)
        if case .path(let p) = lib.cells[0].elements[0] {
            #expect(p.layer == 2)
            #expect(p.width == 10)
            #expect(p.points.count == 2)
            #expect(p.points[0] == IRPoint(x: 0, y: 0))
            #expect(p.points[1] == IRPoint(x: 100, y: 0))
        } else {
            Issue.record("Expected path element")
        }
    }

    @Test func polygonAutoClose() throws {
        let cif = "DS 1 1; L 3; P 0 0 100 0 100 100; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        if case .boundary(let b) = lib.cells[0].elements[0] {
            #expect(b.points.count == 4) // 3 points + auto-close
            #expect(b.points[0] == b.points[3]) // closed
        } else {
            Issue.record("Expected boundary element")
        }
    }

    @Test func cellReference() throws {
        let cif = "DS 2 1; L 1; B 100 100 50 50; DF; DS 1 1; C 2 T 100 200; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        #expect(lib.cells.count == 2)
        let parentCell = lib.cells[1]
        if case .cellRef(let ref) = parentCell.elements[0] {
            #expect(ref.cellName == "CELL_2")
            #expect(ref.origin == IRPoint(x: 100, y: 200))
        } else {
            Issue.record("Expected cellRef element")
        }
    }

    @Test func multipleLayerSwitch() throws {
        let cif = "DS 1 1; L 1; B 100 100 50 50; L 2; B 200 200 100 100; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        #expect(lib.cells[0].elements.count == 2)
        if case .boundary(let b1) = lib.cells[0].elements[0] {
            #expect(b1.layer == 1)
        } else {
            Issue.record("Expected boundary on layer 1")
        }
        if case .boundary(let b2) = lib.cells[0].elements[1] {
            #expect(b2.layer == 2)
        } else {
            Issue.record("Expected boundary on layer 2")
        }
    }

    @Test func scaleFactorConversion() throws {
        // DS 1 2 → scale = 1/2 = 0.5
        let cif = "DS 1 2; L 1; B 200 100 100 50; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        if case .boundary(let b) = lib.cells[0].elements[0] {
            // B 200 100 100 50 with scale 0.5
            // length=100, width=50, cx=50, cy=25
            #expect(b.points[0] == IRPoint(x: 0, y: 0))
            #expect(b.points[2] == IRPoint(x: 100, y: 50))
        } else {
            Issue.record("Expected boundary element")
        }
    }

    @Test func mirrorTransform() throws {
        let cif = "DS 2 1; L 1; B 100 100 50 50; DF; DS 1 1; C 2 M Y; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        let parent = lib.cells[1]
        if case .cellRef(let ref) = parent.elements[0] {
            #expect(ref.transform.mirrorX == true)
        } else {
            Issue.record("Expected cellRef")
        }
    }

    @Test func rotationTransform() throws {
        let cif = "DS 2 1; L 1; B 100 100 50 50; DF; DS 1 1; C 2 R 0 1; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        let parent = lib.cells[1]
        if case .cellRef(let ref) = parent.elements[0] {
            // R 0 1 → atan2(1, 0) = 90 degrees
            let err = abs(ref.transform.angle - 90.0)
            #expect(err < 1e-6)
        } else {
            Issue.record("Expected cellRef")
        }
    }

    @Test func nand2ComplexCell() throws {
        let cif = """
        (NAND2 Cell)
        DS 1 1;
        L 1; B 1200 3000 1000 1500;
        L 2; B 2000 300 1000 750;
        L 2; B 2000 300 1000 1750;
        L 3; W 200 0 200 2000 200;
        L 3; W 200 0 2800 2000 2800;
        9 GND 1000 200;
        9 VDD 1000 2800;
        DF;
        E
        """
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        #expect(lib.cells.count == 1)
        let cell = lib.cells[0]
        // 3 boundaries + 2 paths + 2 texts = 7 elements
        #expect(cell.elements.count == 7)

        var boundaries = 0, paths = 0, texts = 0
        for e in cell.elements {
            switch e {
            case .boundary: boundaries += 1
            case .path: paths += 1
            case .text: texts += 1
            default: break
            }
        }
        #expect(boundaries == 3)
        #expect(paths == 2)
        #expect(texts == 2)
    }

    @Test func namedLayerMapping() throws {
        let cif = "DS 1 1; L METAL1; B 100 100 50 50; L POLY; B 50 50 25 25; L METAL1; B 80 80 40 40; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        let elements = lib.cells[0].elements
        // METAL1 gets layer 1, POLY gets layer 2, second METAL1 reuses layer 1
        if case .boundary(let b1) = elements[0],
           case .boundary(let b2) = elements[1],
           case .boundary(let b3) = elements[2] {
            #expect(b1.layer == b3.layer) // same named layer
            #expect(b1.layer != b2.layer) // different layers
        } else {
            Issue.record("Expected boundary elements")
        }
    }
}
