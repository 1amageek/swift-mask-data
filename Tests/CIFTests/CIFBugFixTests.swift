import Testing
import Foundation
import LayoutIR
@testable import CIF

@Suite("CIF Bug Fixes")
struct CIFBugFixTests {

    @Test func testMirrorXHandling() throws {
        // M X means mirror about X-axis = mirrorX + 180 degree rotation
        let cif = "DS 2 1; L 1; B 100 100 50 50; DF; DS 1 1; C 2 M X T 100 200; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        let parent = lib.cells[1]
        if case .cellRef(let ref) = parent.elements[0] {
            #expect(ref.transform.mirrorX == true)
            // Angle should include 180 degrees from M X
            let angleMod = ref.transform.angle.truncatingRemainder(dividingBy: 360.0)
            #expect(abs(angleMod - 180.0) < 1e-6)
            #expect(ref.origin == IRPoint(x: 100, y: 200))
        } else {
            Issue.record("Expected cellRef element")
        }
    }

    @Test func testMirrorYHandling() throws {
        // M Y means mirror about Y-axis = mirrorX, angle stays 0
        let cif = "DS 2 1; L 1; B 100 100 50 50; DF; DS 1 1; C 2 M Y T 100 200; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        let parent = lib.cells[1]
        if case .cellRef(let ref) = parent.elements[0] {
            #expect(ref.transform.mirrorX == true)
            #expect(abs(ref.transform.angle) < 1e-6)
            #expect(ref.origin == IRPoint(x: 100, y: 200))
        } else {
            Issue.record("Expected cellRef element")
        }
    }

    @Test func testCIFDSThreeParameters() throws {
        // DS 1 100 1000 → scale = 100/1000 = 0.1
        // A box B 1000 500 500 250 → after scaling: 100x50 centered at (50,25)
        let cif = "DS 1 100 1000; L 1; B 1000 500 500 250; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        #expect(lib.cells.count == 1)
        if case .boundary(let b) = lib.cells[0].elements[0] {
            let xs = b.points.map(\.x)
            let ys = b.points.map(\.y)
            // center (50,25), halfL=50, halfW=25
            #expect(xs.min()! == 0)
            #expect(xs.max()! == 100)
            #expect(ys.min()! == 0)
            #expect(ys.max()! == 50)
        } else {
            Issue.record("Expected boundary element")
        }
    }

    @Test func testCIFCombinedMirrorRotation() throws {
        // C 2 M X R 0 1 T 100 200
        // M X sets mirrorX=true, angle += 180
        // R 0 1 adds atan2(1,0) = 90 degrees, so angle = 180 + 90 = 270
        let cif = "DS 2 1; L 1; B 100 100 50 50; DF; DS 1 1; C 2 M X R 0 1 T 100 200; DF; E"
        let lib = try CIFLibraryReader.read(Data(cif.utf8))
        let parent = lib.cells[1]
        if case .cellRef(let ref) = parent.elements[0] {
            #expect(ref.transform.mirrorX == true)
            // angle should be 180 (from M X) + 90 (from R 0 1) = 270
            let expectedAngle = 270.0
            let angleMod = ref.transform.angle.truncatingRemainder(dividingBy: 360.0)
            #expect(abs(angleMod - expectedAngle) < 1e-6)
            #expect(ref.origin == IRPoint(x: 100, y: 200))
        } else {
            Issue.record("Expected cellRef element")
        }
    }

    @Test func testScaleFactorWriteRoundTrip() throws {
        // Create a library with known coordinates
        let cell = IRCell(name: "CELL_1", elements: [
            .boundary(IRBoundary(layer: 1, datatype: 0, points: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 100, y: 0),
                IRPoint(x: 100, y: 50),
                IRPoint(x: 0, y: 50),
                IRPoint(x: 0, y: 0),
            ], properties: [])),
            .path(IRPath(layer: 1, datatype: 0, pathType: .flush,
                        width: 10, points: [
                            IRPoint(x: 0, y: 0),
                            IRPoint(x: 200, y: 0),
                        ], properties: [])),
            .text(IRText(layer: 1, texttype: 0, transform: .identity,
                        position: IRPoint(x: 50, y: 25),
                        string: "LABEL", properties: []))
        ])
        let lib = IRLibrary(name: "test", units: .default, cells: [cell])

        // Write with scaleFactor=100
        let options = CIFLibraryWriter.Options(scaleFactor: 100)
        let data = try CIFLibraryWriter.write(lib, options: options)

        // Read back
        let result = try CIFLibraryReader.read(data)
        #expect(result.cells.count == 1)
        let elements = result.cells[0].elements

        // Verify boundary coordinates round-trip correctly
        if case .boundary(let b) = elements[0] {
            let xs = b.points.map(\.x)
            let ys = b.points.map(\.y)
            #expect(xs.min()! == 0)
            #expect(xs.max()! == 100)
            #expect(ys.min()! == 0)
            #expect(ys.max()! == 50)
        } else {
            Issue.record("Expected boundary element")
        }

        // Verify path coordinates round-trip correctly
        if case .path(let p) = elements[1] {
            #expect(p.width == 10)
            #expect(p.points[0] == IRPoint(x: 0, y: 0))
            #expect(p.points[1] == IRPoint(x: 200, y: 0))
        } else {
            Issue.record("Expected path element")
        }

        // Verify text position round-trip correctly
        if case .text(let t) = elements[2] {
            #expect(t.position == IRPoint(x: 50, y: 25))
        } else {
            Issue.record("Expected text element")
        }
    }
}
