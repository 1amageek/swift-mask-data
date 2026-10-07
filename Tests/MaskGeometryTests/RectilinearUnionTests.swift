import Testing
import LayoutIR
import MaskGeometry

@Suite("Aggregate bounded exact rectilinear union", .timeLimit(.minutes(1)))
struct RectilinearUnionTests {
    private func polygon(_ coordinates: [(Int32, Int32)]) -> IRBoundary {
        .init(layer: 7, datatype: 0, points: coordinates.map { .init(x: $0.0, y: $0.1) })
    }
    private func box(_ minX: Int32, _ minY: Int32, _ maxX: Int32, _ maxY: Int32) -> IRBoundary {
        polygon([(minX, minY), (maxX, minY), (maxX, maxY), (minX, maxY), (minX, minY)])
    }
    private var rectangle: Region { Region(polygons: [box(0, 0, 4, 3)]) }
    private func limits(input: Int = 1_000, edges: Int = 1_000, intermediate: Int = 1_000,
                        work: Int = 10_000, output: Int = 1_000) -> RectilinearUnionLimits {
        .init(maximumInputEntries: input, maximumEdgeProbes: edges,
              maximumIntermediateBands: intermediate, maximumSweepWork: work, maximumOutputBands: output)
    }

    @Test func overlappingPiecesCoalesceAndRetainCallerOwnership() throws {
        let region = Region(polygons: [box(0, 0, 4, 3), box(2, 0, 6, 3), box(6, 0, 8, 3)])
        var budget = try RectilinearUnionBudget(limits: limits())
        let bands = try region.rectilinearUnionBands(toPolygonIndex: 41, budget: &budget)
        #expect(bands.count == 1)
        let band = try #require(bands.first)
        #expect(band.polygonIndex == 41)
        #expect(band.minX == 0 && band.maxX == 8 && band.minY == 0 && band.maxY == 3)
        #expect(budget.remainingInputEntries == 982 && budget.remainingEdgeProbes == 988)
        #expect(budget.remainingIntermediateBands == 997 && budget.remainingOutputBands == 999)
    }

    @Test func concavityHolesDuplicatesAndOrderMatchExactLegacyUnion() throws {
        let concave = polygon([(0, 0), (4, 0), (4, 1), (1, 1), (1, 3), (0, 3)])
        let hole = polygon([(10, 0), (16, 0), (16, 6), (10, 6), (10, 0),
            (12, 0), (12, 2), (12, 4), (14, 4), (14, 2), (12, 2), (12, 0), (10, 0)])
        let piece = box(-4, -3, -1, -1)
        let region = Region(polygons: [concave, hole, piece])
        var budget = try RectilinearUnionBudget(limits: limits())
        let bands = try region.rectilinearUnionBands(toPolygonIndex: 0, budget: &budget)
        let recomposed = Region(polygons: bands.map { box($0.minX, $0.minY, $0.maxX, $0.maxY) })
        let expected = Region(polygons: [box(0, 0, 4, 1), box(0, 1, 1, 3),
            box(10, 0, 16, 2), box(10, 2, 12, 4), box(14, 2, 16, 4), box(10, 4, 16, 6), piece])
        #expect(try recomposed.symmetricDifference(expected).isEmpty)
        #expect(try region.union(Region()).symmetricDifference(recomposed).isEmpty)
        #expect(recomposed.area == 44)
        #expect(!recomposed.contains(.init(x: 13, y: 3)))
        #expect(!recomposed.contains(.init(x: 3, y: 2)))
        var otherBudget = try RectilinearUnionBudget(limits: limits())
        let permuted = try Region(polygons: [piece, hole, concave, concave, hole])
            .rectilinearUnionBands(toPolygonIndex: 0, budget: &otherBudget)
        #expect(permuted == bands)
    }

    @Test func int32ExtremeEndpointsAndOneUnitRowsRemainExact() throws {
        var budget = try RectilinearUnionBudget(limits: limits())
        let bands = try Region(polygons: [box(.min, .max - 1, 0, .max), box(0, .max - 1, .max, .max)])
            .rectilinearUnionBands(toPolygonIndex: .max, budget: &budget)
        #expect(bands.count == 1)
        let band = try #require(bands.first)
        #expect(band.minX == .min && band.maxX == .max && band.minY == .max - 1 && band.maxY == .max)
        #expect(band.polygonIndex == .max)
    }

    @Test(arguments: [0, 1, 2, 3, 4])
    func eachAdmissionCeilingRefusesWithoutPublishing(resource: Int) throws {
        // A rectangle has six input entries, four edge probes, one intermediate
        // band, six sweep visits and one provisional output band.
        let admitted = limits(input: 6, edges: 4, intermediate: 1, work: 6, output: 1)
        var exact = try RectilinearUnionBudget(limits: admitted)
        #expect(try rectangle.rectilinearUnionBands(toPolygonIndex: 0, budget: &exact).count == 1)
        #expect(exact.remainingInputEntries == 0 && exact.remainingEdgeProbes == 0)
        #expect(exact.remainingIntermediateBands == 0 && exact.remainingSweepWork == 0 && exact.remainingOutputBands == 0)
        var budget = try RectilinearUnionBudget(limits: limits(input: resource == 0 ? 5 : 6,
            edges: resource == 1 ? 3 : 4, intermediate: resource == 2 ? 0 : 1,
            work: resource == 3 ? 5 : 6, output: resource == 4 ? 0 : 1))
        let expected: RectilinearDecompositionError.Resource = resource == 0 ? .inputEntries
            : resource == 1 ? .edgeProbes : resource == 2 ? .intermediateBands
            : resource == 3 ? .sweepWork : .outputBands
        var result: [RectilinearBand]?
        #expect(throws: RectilinearDecompositionError.limitExceeded(expected)) {
            result = try rectangle.rectilinearUnionBands(toPolygonIndex: 0, budget: &budget)
        }
        #expect(result == nil)
        if resource > 0 { #expect(budget.remainingInputEntries == 0) }
        if resource > 1 { #expect(budget.remainingEdgeProbes == 0) }
        if resource > 2 { #expect(budget.remainingIntermediateBands == 0) }
        if resource == 3 { #expect(budget.remainingSweepWork == 0) }
        if resource == 4 { #expect(budget.remainingSweepWork == 0) }
    }

    @Test(arguments: [0, 1, 2, 3, 4])
    func negativeLimitsFailAtBudgetCreation(resource: Int) {
        #expect(throws: RectilinearDecompositionError.invalidLimits) {
            try RectilinearUnionBudget(limits: limits(input: resource == 0 ? -1 : 0,
                edges: resource == 1 ? -1 : 0, intermediate: resource == 2 ? -1 : 0,
                work: resource == 3 ? -1 : 0, output: resource == 4 ? -1 : 0))
        }
    }

    @Test func invalidOwnerAndUnsupportedPrefixPreserveSpentBudget() throws {
        var budget = try RectilinearUnionBudget(limits: limits())
        let initial = budget
        #expect(throws: RectilinearDecompositionError.invalidUnionPolygonIndex) {
            try rectangle.rectilinearUnionBands(toPolygonIndex: -1, budget: &budget)
        }
        #expect(budget == initial)
        let region = Region(polygons: [box(0, 0, 4, 3), polygon([(0, 0), (4, 0), (0, 4)])])
        var result: [RectilinearBand]?
        #expect(throws: RectilinearDecompositionError.unsupportedNonManhattanGeometry(polygonIndex: 1)) {
            result = try region.rectilinearUnionBands(toPolygonIndex: 0, budget: &budget)
        }
        #expect(result == nil)
        #expect(budget.remainingInputEntries == 990 && budget.remainingEdgeProbes == 996)
        #expect(budget.remainingIntermediateBands == 999 && budget.remainingOutputBands == 1_000)
    }

    @Test func aggregateBudgetCannotResetBetweenRegionsOrAfterFailure() throws {
        var budget = try RectilinearUnionBudget(limits: limits(input: 12, edges: 8, intermediate: 2, work: 12, output: 2))
        #expect(try rectangle.rectilinearUnionBands(toPolygonIndex: 0, budget: &budget).count == 1)
        #expect(try rectangle.rectilinearUnionBands(toPolygonIndex: 1, budget: &budget).count == 1)
        let spent = budget
        #expect(throws: RectilinearDecompositionError.limitExceeded(.inputEntries)) {
            try rectangle.rectilinearUnionBands(toPolygonIndex: 2, budget: &budget)
        }
        #expect(budget == spent)
        var edgeBudget = try RectilinearUnionBudget(limits: limits(input: 12, edges: 3))
        #expect(throws: RectilinearDecompositionError.limitExceeded(.edgeProbes)) {
            try rectangle.rectilinearUnionBands(toPolygonIndex: 0, budget: &edgeBudget)
        }
        #expect(edgeBudget.remainingInputEntries == 6 && edgeBudget.remainingEdgeProbes == 0)
        #expect(throws: RectilinearDecompositionError.limitExceeded(.edgeProbes)) {
            try rectangle.rectilinearUnionBands(toPolygonIndex: 0, budget: &edgeBudget)
        }
        #expect(edgeBudget.remainingInputEntries == 0 && edgeBudget.remainingEdgeProbes == 0)
    }

    @Test func emptyCoverageAndInitialCancellationAreExplicit() throws {
        var budget = try RectilinearUnionBudget(limits: limits(input: 0, edges: 0, intermediate: 0, work: 0, output: 0))
        #expect(try Region().rectilinearUnionBands(toPolygonIndex: 0, budget: &budget).isEmpty)
        #expect(throws: RectilinearDecompositionError.cancelled) {
            try Region().rectilinearUnionBands(toPolygonIndex: 0, budget: &budget, isCancelled: { true })
        }
        #expect(budget.remainingInputEntries == 0 && budget.remainingOutputBands == 0)
    }

    @Test func cancellationWithinSweepDoesNotPublishOrRefund() throws {
        let region = Region(polygons: [box(0, 0, 4, 2), box(0, 2, 4, 4)])
        var measuredBudget = try RectilinearUnionBudget(limits: limits())
        var checks = 0
        let complete = try region.rectilinearUnionBands(toPolygonIndex: 0, budget: &measuredBudget,
            isCancelled: { checks += 1; return false })
        #expect(complete.count == 1)
        var budget = try RectilinearUnionBudget(limits: limits())
        var cancelledChecks = 0
        var result: [RectilinearBand]?
        #expect(throws: RectilinearDecompositionError.cancelled) {
            result = try region.rectilinearUnionBands(toPolygonIndex: 0, budget: &budget, isCancelled: {
                cancelledChecks += 1
                return cancelledChecks >= checks - 3
            })
        }
        #expect(result == nil && budget.remainingInputEntries == 988 && budget.remainingEdgeProbes == 992)
        #expect(budget.remainingIntermediateBands == 998 && budget.remainingOutputBands == 998)
        #expect(budget.remainingSweepWork < 10_000)
    }

    @Test func provisionalRowsAreAdmittedBeforeFinalVerticalMerge() throws {
        let region = Region(polygons: [box(0, 0, 4, 2), box(0, 2, 4, 4)])
        var enough = try RectilinearUnionBudget(limits: limits(output: 2))
        let bands = try region.rectilinearUnionBands(toPolygonIndex: 0, budget: &enough)
        #expect(bands.count == 1 && enough.remainingOutputBands == 0)
        var insufficient = try RectilinearUnionBudget(limits: limits(output: 1))
        var result: [RectilinearBand]?
        #expect(throws: RectilinearDecompositionError.limitExceeded(.outputBands)) {
            result = try region.rectilinearUnionBands(toPolygonIndex: 0, budget: &insufficient)
        }
        #expect(result == nil && insufficient.remainingOutputBands == 0)
        #expect(insufficient.remainingIntermediateBands == 998)
    }
}
