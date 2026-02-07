import Testing
import Foundation
import LayoutIR
@testable import OASIS

// MARK: - Step 6: Point List

@Suite("OASIS Point List")
struct OASISPointListTests {
    @Test func generalRectangle() throws {
        // Write 4 delta points forming a rectangle
        let deltas: [IRPoint] = [
            IRPoint(x: 100, y: 0),
            IRPoint(x: 0, y: 50),
            IRPoint(x: -100, y: 0),
            IRPoint(x: 0, y: -50),
        ]
        var writer = OASISWriter()
        writer.writePointList(deltas)
        var reader = OASISReader(data: writer.data)
        let decoded = try reader.readPointList()
        #expect(decoded == deltas)
    }

    @Test func singlePoint() throws {
        let deltas: [IRPoint] = [IRPoint(x: 42, y: -17)]
        var writer = OASISWriter()
        writer.writePointList(deltas)
        var reader = OASISReader(data: writer.data)
        let decoded = try reader.readPointList()
        #expect(decoded == deltas)
    }

    @Test func negativeCoordinates() throws {
        let deltas: [IRPoint] = [
            IRPoint(x: -200, y: -300),
            IRPoint(x: 500, y: 100),
            IRPoint(x: -300, y: 200),
        ]
        var writer = OASISWriter()
        writer.writePointList(deltas)
        var reader = OASISReader(data: writer.data)
        let decoded = try reader.readPointList()
        #expect(decoded == deltas)
    }

    @Test func emptyPointList() throws {
        let deltas: [IRPoint] = []
        var writer = OASISWriter()
        writer.writePointList(deltas)
        var reader = OASISReader(data: writer.data)
        let decoded = try reader.readPointList()
        #expect(decoded.isEmpty)
    }

    @Test func largeCoordinates() throws {
        let deltas: [IRPoint] = [
            IRPoint(x: 32767, y: -32768),
            IRPoint(x: -32767, y: 32768),
        ]
        var writer = OASISWriter()
        writer.writePointList(deltas)
        var reader = OASISReader(data: writer.data)
        let decoded = try reader.readPointList()
        #expect(decoded == deltas)
    }
}

// MARK: - Step 7: Modal State

@Suite("OASIS Modal State")
struct OASISModalStateTests {
    @Test func initialStateIsNil() {
        let state = OASISModalState()
        #expect(state.layer == nil)
        #expect(state.datatype == nil)
        #expect(state.textlayer == nil)
        #expect(state.texttype == nil)
        #expect(state.x == nil)
        #expect(state.y == nil)
        #expect(state.geometryW == nil)
        #expect(state.geometryH == nil)
        #expect(state.pathHalfwidth == nil)
        #expect(state.cellName == nil)
        #expect(state.textString == nil)
    }

    @Test func resetClearsAll() {
        var state = OASISModalState()
        state.layer = 5
        state.datatype = 0
        state.x = 100
        state.y = 200
        state.cellName = "TOP"
        state.reset()
        #expect(state.layer == nil)
        #expect(state.datatype == nil)
        #expect(state.x == nil)
        #expect(state.y == nil)
        #expect(state.cellName == nil)
    }

    @Test func setAndRetrieve() {
        var state = OASISModalState()
        state.layer = 3
        state.datatype = 1
        state.x = -500
        state.y = 1000
        state.geometryW = 200
        state.geometryH = 100
        state.pathHalfwidth = 50
        state.cellName = "NAND2"
        state.textString = "VDD"
        #expect(state.layer == 3)
        #expect(state.datatype == 1)
        #expect(state.x == -500)
        #expect(state.y == 1000)
        #expect(state.geometryW == 200)
        #expect(state.geometryH == 100)
        #expect(state.pathHalfwidth == 50)
        #expect(state.cellName == "NAND2")
        #expect(state.textString == "VDD")
    }
}

// MARK: - Step 7: Repetition

@Suite("OASIS Repetition")
struct OASISRepetitionTests {
    @Test func gridRoundTrip() throws {
        let rep = OASISRepetition.grid(columns: 4, rows: 3, colSpacing: 100, rowSpacing: 200)
        var writer = OASISWriter()
        writer.writeRepetition(rep)
        var reader = OASISReader(data: writer.data)
        let decoded = try reader.readRepetition()
        #expect(decoded == rep)
    }

    @Test func uniformRowRoundTrip() throws {
        let rep = OASISRepetition.uniformRow(count: 10, spacing: 50)
        var writer = OASISWriter()
        writer.writeRepetition(rep)
        var reader = OASISReader(data: writer.data)
        let decoded = try reader.readRepetition()
        #expect(decoded == rep)
    }

    @Test func uniformColumnRoundTrip() throws {
        let rep = OASISRepetition.uniformColumn(count: 5, spacing: 75)
        var writer = OASISWriter()
        writer.writeRepetition(rep)
        var reader = OASISReader(data: writer.data)
        let decoded = try reader.readRepetition()
        #expect(decoded == rep)
    }

    @Test func variableRowRoundTrip() throws {
        let rep = OASISRepetition.variableRow(spacings: [100, 200, 150])
        var writer = OASISWriter()
        writer.writeRepetition(rep)
        var reader = OASISReader(data: writer.data)
        let decoded = try reader.readRepetition()
        #expect(decoded == rep)
    }

    @Test func variableColumnRoundTrip() throws {
        let rep = OASISRepetition.variableColumn(spacings: [50, 60, 70, 80])
        var writer = OASISWriter()
        writer.writeRepetition(rep)
        var reader = OASISReader(data: writer.data)
        let decoded = try reader.readRepetition()
        #expect(decoded == rep)
    }

    @Test func gridMinimumSize() throws {
        // Minimum grid: 2×2
        let rep = OASISRepetition.grid(columns: 2, rows: 2, colSpacing: 10, rowSpacing: 20)
        var writer = OASISWriter()
        writer.writeRepetition(rep)
        var reader = OASISReader(data: writer.data)
        let decoded = try reader.readRepetition()
        #expect(decoded == rep)
    }
}
