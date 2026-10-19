import Foundation
import Testing
@testable import LEF

@Suite("Standard LEF parallel-run-length tables", .timeLimit(.minutes(1)))
struct LEFStandardSpacingTableTests {
    private func read(_ body: String) throws -> LEFLayerDef {
        let source = "VERSION 5.8 ;\nLAYER m1\nTYPE ROUTING ;\n\(body)\nEND m1\nEND LIBRARY\n"
        return try #require(LEFLibraryReader.read(Data(source.utf8)).layers.first)
    }

    @Test func standardSingleTerminator() throws {
        let layer = try read("""
        SPACINGTABLE PARALLELRUNLENGTH 0 0.5 1
          WIDTH 0 0.1 0.2 0.3
          WIDTH 0.4 0.2 0.3 0.4 ;
        WIDTH 0.14 ;
        THICKNESS 0.1 ;
        """)
        let table = try #require(layer.spacingTable)
        #expect(table.parallelRunLengths == [0, 0.5, 1])
        #expect(table.widthEntries == [.init(width: 0, spacings: [0.1, 0.2, 0.3]),
                                      .init(width: 0.4, spacings: [0.2, 0.3, 0.4])])
        #expect(layer.width == 0.14)
        #expect(layer.thickness == 0.1)
    }

    @Test func legacyRowsRemainReadable() throws {
        let layer = try read("""
        WIDTH 0.14 ;
        SPACINGTABLE PARALLELRUNLENGTH 0 0.5 ;
          WIDTH 0 0.1 0.2 ;
          WIDTH 0.4 0.2 0.3 ;
        THICKNESS 0.1 ;
        """)
        #expect(layer.spacingTable?.widthEntries.count == 2)
        #expect(layer.width == 0.14)
        #expect(layer.thickness == 0.1)
    }

    @Test func writerEmitsStandardGrammar() throws {
        let table = LEFSpacingTable(parallelRunLengths: [0, 0.5], widthEntries: [
            .init(width: 0, spacings: [0.1, 0.2]), .init(width: 0.4, spacings: [0.2, 0.3])
        ])
        let document = LEFDocument(layers: [.init(name: "m1", type: .routing, width: 0.14, spacingTable: table)])
        let bytes = try LEFLibraryWriter.write(document)
        let text = try #require(String(data: bytes, encoding: .utf8))
        let start = try #require(text.range(of: "SPACINGTABLE"))
        let end = try #require(text.range(of: "END m1", range: start.upperBound..<text.endIndex))
        #expect(text[start.lowerBound..<end.lowerBound].filter { $0 == ";" }.count == 1)
        #expect(try LEFLibraryReader.read(bytes).layers.first?.spacingTable == table)
    }

    @Test(arguments: [
        "PARALLELRUNLENGTH ;", "PARALLELRUNLENGTH 0 ;",
        "PARALLELRUNLENGTH 0 1 WIDTH 0 0.1 ;",
        "PARALLELRUNLENGTH 0 WIDTH 0 0.1 0.2 ;",
        "PARALLELRUNLENGTH 1 0 WIDTH 0 0.1 0.2 ;",
        "PARALLELRUNLENGTH 0 0 WIDTH 0 0.1 0.2 ;",
        "PARALLELRUNLENGTH 0 WIDTH -1 0.1 ;",
        "PARALLELRUNLENGTH 0 WIDTH 1 0.1 WIDTH 0 0.2 ;",
        "PARALLELRUNLENGTH 0 WIDTH 0 0.1 WIDTH 0 0.2 ;",
        "PARALLELRUNLENGTH 0 1 WIDTH 0 0.2 0.1 ;",
        "PARALLELRUNLENGTH 0 WIDTH 0 0.2 WIDTH 1 0.1 ;",
        "PARALLELRUNLENGTH 0 WIDTH 0 -0.1 ;",
        "PARALLELRUNLENGTH 0 WIDTH 0 0.1 SPACING 0.2 ;",
        "PARALLELRUNLENGTH 0 WIDTH 0 0.1",
        "TWOWIDTHS WIDTH 0 0.1 ;"
    ])
    func malformedTextFails(_ body: String) {
        #expect(throws: LEFError.self) { _ = try read("SPACINGTABLE \(body)") }
    }

    @Test(arguments: [
        LEFSpacingTable(parallelRunLengths: [], widthEntries: [.init(width: 0, spacings: [])]),
        LEFSpacingTable(parallelRunLengths: [0], widthEntries: []),
        LEFSpacingTable(parallelRunLengths: [0, 1], widthEntries: [.init(width: 0, spacings: [0.1])]),
        LEFSpacingTable(parallelRunLengths: [0, 0], widthEntries: [.init(width: 0, spacings: [0.1, 0.2])]),
        LEFSpacingTable(parallelRunLengths: [0], widthEntries: [.init(width: 0, spacings: [-1])]),
        LEFSpacingTable(parallelRunLengths: [0], widthEntries: [.init(width: 0, spacings: [.infinity])]),
        LEFSpacingTable(parallelRunLengths: [.nan], widthEntries: [.init(width: 0, spacings: [0.1])]),
        LEFSpacingTable(parallelRunLengths: [0], widthEntries: [.init(width: .infinity, spacings: [0.1])]),
        LEFSpacingTable(parallelRunLengths: [0, 1], widthEntries: [.init(width: 0, spacings: [0.2, 0.1])]),
        LEFSpacingTable(parallelRunLengths: [0], widthEntries: [.init(width: 0, spacings: [0.2]), .init(width: 1, spacings: [0.1])])
    ])
    func malformedOwnedValueFails(_ table: LEFSpacingTable) {
        #expect(throws: LEFError.self) {
            _ = try LEFLibraryWriter.write(LEFDocument(layers: [.init(name: "m1", type: .routing, spacingTable: table)]))
        }
    }

    @Test func signedParallelLengthIsRetained() throws {
        let layer = try read("SPACINGTABLE PARALLELRUNLENGTH -0.5 0 0.5 WIDTH 0 0.1 0.2 0.3 ;")
        #expect(layer.spacingTable?.parallelRunLengths == [-0.5, 0, 0.5])
        let bytes = try LEFLibraryWriter.write(LEFDocument(layers: [layer]))
        #expect(try LEFLibraryReader.read(bytes).layers.first?.spacingTable == layer.spacingTable)
    }

    @Test(arguments: [true, false])
    func conflictingScalarSpacingFails(_ scalarFirst: Bool) {
        let table = "SPACINGTABLE PARALLELRUNLENGTH 0 WIDTH 0 0.1 ;"
        let scalar = "SPACING 0.2 ;"
        #expect(throws: LEFError.self) { _ = try read(scalarFirst ? "\(scalar) \(table)" : "\(table) \(scalar)") }
        #expect(throws: LEFError.self) {
            _ = try LEFLibraryWriter.write(LEFDocument(layers: [.init(name: "m1", type: .routing,
                spacing: 0.2, spacingTable: .init(parallelRunLengths: [0], widthEntries: [.init(width: 0, spacings: [0.1])]))]))
        }
    }
}
