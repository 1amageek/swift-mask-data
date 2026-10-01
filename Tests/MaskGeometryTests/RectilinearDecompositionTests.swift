import Testing
import LayoutIR
import MaskGeometry

@Suite("Bounded exact rectilinear decomposition", .timeLimit(.minutes(1)))
struct RectilinearDecompositionTests {
    private func polygon(_ coordinates: [(Int32, Int32)]) -> IRBoundary {
        IRBoundary(layer: 7, datatype: 0, points: coordinates.map { IRPoint(x: $0.0, y: $0.1) })
    }
    private var rectangle: IRBoundary { polygon([(0, 0), (4, 0), (4, 3), (0, 3), (0, 0)]) }

    @Test func rectangleHasExactBandAndInputBoundary() throws {
        let limits = RectilinearDecompositionLimits(maximumInputEntries: 6, maximumEdgeProbes: 4, maximumOutputBands: 1)
        let bands = try Region(polygons: [rectangle]).rectilinearBands(limits: limits)
        #expect(bands.count == 1 && bands[0].polygonIndex == 0)
        #expect(bands[0].minX == 0 && bands[0].maxX == 4 && bands[0].minY == 0 && bands[0].maxY == 3)
    }
    @Test func concavePolygonIsNotReplacedByItsBoundingBox() throws {
        let input = polygon([(0, 0), (4, 0), (4, 1), (1, 1), (1, 3), (0, 3)])
        let bands = try Region(polygons: [input]).rectilinearBands()
        #expect(bands.count == 2)
        #expect(bands[0].minX == 0 && bands[0].maxX == 4 && bands[0].minY == 0 && bands[0].maxY == 1)
        #expect(bands[1].minX == 0 && bands[1].maxX == 1 && bands[1].minY == 1 && bands[1].maxY == 3)
    }
    @Test func stitchedHoleRetainsEmptyInterior() throws {
        let input = polygon([(0, 0), (6, 0), (6, 6), (0, 6), (0, 0),
                             (2, 0), (2, 2), (2, 4), (4, 4), (4, 2), (2, 2), (2, 0), (0, 0)])
        let region = Region(polygons: [input])
        let bands = try region.rectilinearBands()
        #expect(bands.count == 5)
        #expect(bands.reduce(Int64(0)) { sum, band in
            sum + (Int64(band.maxX) - Int64(band.minX)) * (Int64(band.maxY) - Int64(band.minY))
        } == 32)
        #expect(!bands.contains { $0.minX < 3 && 3 < $0.maxX && $0.minY < 3 && 3 < $0.maxY })
        let recomposed = Region(polygons: bands.map {
            polygon([($0.minX, $0.minY), ($0.maxX, $0.minY), ($0.maxX, $0.maxY), ($0.minX, $0.maxY)])
        })
        #expect(try region.symmetricDifference(recomposed).isEmpty)
    }
    @Test func sourcePolygonIdentityAndOverlapArePreserved() throws {
        let input = Region(polygons: [rectangle, polygon([(2, 1), (6, 1), (6, 4), (2, 4)])])
        let bands = try input.rectilinearBands()
        #expect(bands.map(\.polygonIndex) == [0, 1])
        #expect(bands[0].maxX == 4 && bands[1].minX == 2)
    }
    @Test func int32EndpointsAndOneUnitRowsRemainExact() throws {
        let input = polygon([(.min, .max - 1), (.max, .max - 1), (.max, .max), (.min, .max)])
        let bands = try Region(polygons: [input]).rectilinearBands()
        #expect(bands.count == 1)
        #expect(bands[0].minX == .min && bands[0].maxX == .max)
        #expect(bands[0].minY == .max - 1 && bands[0].maxY == .max)
    }
    @Test func nonManhattanGeometryRejectsEvenAfterValidPrefix() {
        let region = Region(polygons: [rectangle, polygon([(0, 0), (4, 0), (0, 4)])])
        #expect(throws: RectilinearDecompositionError.unsupportedNonManhattanGeometry(polygonIndex: 1)) {
            try region.rectilinearBands()
        }
    }
    @Test func degenerateCoverageAndEmptyInputAreExplicit() throws {
        #expect(try Region().rectilinearBands(limits: .init(maximumInputEntries: 0, maximumEdgeProbes: 0, maximumOutputBands: 0)).isEmpty)
        let input = Region(polygons: [polygon([]), polygon([(0, 0), (1, 0), (2, 0)])])
        #expect(try input.rectilinearBands().isEmpty)
    }
    @Test(arguments: [0, 1, 2]) func eachAdmissionBoundaryRejects(resource: Int) {
        let limits = RectilinearDecompositionLimits(maximumInputEntries: resource == 0 ? 5 : 6,
            maximumEdgeProbes: resource == 1 ? 3 : 4, maximumOutputBands: resource == 2 ? 0 : 1)
        let expected: RectilinearDecompositionError.Resource = resource == 0 ? .inputEntries : resource == 1 ? .edgeProbes : .outputBands
        #expect(throws: RectilinearDecompositionError.limitExceeded(expected)) {
            try Region(polygons: [rectangle]).rectilinearBands(limits: limits)
        }
    }
    @Test func polygonMetadataAndCumulativeBudgetsCannotBypassAdmission() {
        #expect(throws: RectilinearDecompositionError.limitExceeded(.inputEntries)) {
            try Region(polygons: [polygon([]), polygon([])]).rectilinearBands(
                limits: .init(maximumInputEntries: 1, maximumEdgeProbes: 0, maximumOutputBands: 0))
        }
        #expect(throws: RectilinearDecompositionError.limitExceeded(.edgeProbes)) {
            try Region(polygons: [rectangle, rectangle]).rectilinearBands(
                limits: .init(maximumInputEntries: 12, maximumEdgeProbes: 7, maximumOutputBands: 2))
        }
        #expect(throws: RectilinearDecompositionError.limitExceeded(.outputBands)) {
            try Region(polygons: [rectangle, rectangle]).rectilinearBands(
                limits: .init(maximumInputEntries: 12, maximumEdgeProbes: 8, maximumOutputBands: 1))
        }
    }
    @Test func invalidLimitsRejectBeforeDecomposition() {
        #expect(throws: RectilinearDecompositionError.invalidLimits) {
            try Region().rectilinearBands(limits: .init(maximumInputEntries: -1, maximumEdgeProbes: 0, maximumOutputBands: 0))
        }
    }
    @Test func initialCancellationIsHonoredForEmptyInput() {
        #expect(throws: RectilinearDecompositionError.cancelled) { try Region().rectilinearBands(isCancelled: { true }) }
    }
    @Test func cancellationAfterAnEmittedPrefixDoesNotPublishPartialOutput() {
        var checks = 0
        var output: [RectilinearBand]?
        #expect(throws: RectilinearDecompositionError.cancelled) {
            output = try Region(polygons: [rectangle, rectangle]).rectilinearBands(isCancelled: {
                checks += 1
                return checks >= 21
            })
        }
        #expect(checks == 21 && output == nil)
    }
}
