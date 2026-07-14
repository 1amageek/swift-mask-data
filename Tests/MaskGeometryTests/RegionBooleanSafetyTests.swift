import Testing
import LayoutIR
@testable import MaskGeometry

@Suite("Region boolean safety")
struct RegionBooleanSafetyTests {
    @Test func checkedOperationRejectsNonManhattanGeometryWithoutFallback() {
        let triangle = Region(polygons: [IRBoundary(
            layer: 1,
            datatype: 0,
            points: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 10, y: 0),
                IRPoint(x: 0, y: 10),
                IRPoint(x: 0, y: 0),
            ],
            properties: []
        )])
        let rectangle = Region(polygons: [IRBoundary(
            layer: 1,
            datatype: 0,
            points: [
                IRPoint(x: 0, y: 0),
                IRPoint(x: 10, y: 0),
                IRPoint(x: 10, y: 10),
                IRPoint(x: 0, y: 10),
                IRPoint(x: 0, y: 0),
            ],
            properties: []
        )])

        do {
            _ = try triangle.andChecked(rectangle)
            Issue.record("Expected exact-only boolean operation to reject non-Manhattan input")
        } catch let error as RegionBooleanError {
            #expect(error == .unsupportedNonManhattanGeometry(operand: "left", polygonIndex: 0))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func checkedOperationPreservesExactManhattanResult() throws {
        let first = Region(polygons: [box(x1: 0, y1: 0, x2: 100, y2: 100)])
        let second = Region(polygons: [box(x1: 50, y1: 0, x2: 150, y2: 100)])
        let result = try first.andChecked(second)
        #expect(result.area == 5_000)
    }

    private func box(x1: Int32, y1: Int32, x2: Int32, y2: Int32) -> IRBoundary {
        IRBoundary(
            layer: 1,
            datatype: 0,
            points: [
                IRPoint(x: x1, y: y1),
                IRPoint(x: x2, y: y1),
                IRPoint(x: x2, y: y2),
                IRPoint(x: x1, y: y2),
                IRPoint(x: x1, y: y1),
            ],
            properties: []
        )
    }
}
