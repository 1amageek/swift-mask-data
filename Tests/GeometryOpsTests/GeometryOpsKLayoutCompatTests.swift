import Testing
import Foundation
import LayoutIR
@testable import GeometryOps

// MARK: - Helpers

func makeTriangle(layer: Int16 = 1, x1: Int32, y1: Int32, x2: Int32, y2: Int32, x3: Int32, y3: Int32) -> IRBoundary {
    IRBoundary(layer: layer, datatype: 0, points: [
        IRPoint(x: x1, y: y1), IRPoint(x: x2, y: y2),
        IRPoint(x: x3, y: y3), IRPoint(x: x1, y: y1),
    ], properties: [])
}

func makeHexagon(layer: Int16 = 1, cx: Int32, cy: Int32, radius: Int32) -> IRBoundary {
    var points: [IRPoint] = []
    for i in 0..<6 {
        let angle = Double(i) / 6.0 * 2.0 * .pi
        let px = cx + Int32(Double(radius) * cos(angle))
        let py = cy + Int32(Double(radius) * sin(angle))
        points.append(IRPoint(x: px, y: py))
    }
    points.append(points[0])
    return IRBoundary(layer: layer, datatype: 0, points: points, properties: [])
}

// MARK: - Non-Manhattan Boolean

@Suite("Non-Manhattan Boolean")
struct NonManhattanBooleanTests {

    @Test func triangleAnd() {
        // Two overlapping triangles
        let a = Region(layer: 1, polygons: [
            makeTriangle(x1: 0, y1: 0, x2: 100, y2: 0, x3: 50, y3: 100)
        ])
        let b = Region(layer: 1, polygons: [
            makeTriangle(x1: 0, y1: 100, x2: 100, y2: 100, x3: 50, y3: 0)
        ])
        let result = a.and(b)
        #expect(!result.isEmpty)
        #expect(result.area > 0)
    }

    @Test func hexagonAnd() {
        let hex1 = makeHexagon(cx: 0, cy: 0, radius: 100)
        let hex2 = makeHexagon(cx: 50, cy: 0, radius: 100)
        let a = Region(layer: 1, polygons: [hex1])
        let b = Region(layer: 1, polygons: [hex2])
        let result = a.and(b)
        #expect(!result.isEmpty)
        // Intersection should be smaller than either hexagon
        #expect(result.area < a.area)
        #expect(result.area < b.area)
    }

    @Test func triangleOr() {
        let a = Region(layer: 1, polygons: [
            makeTriangle(x1: 0, y1: 0, x2: 100, y2: 0, x3: 50, y3: 100)
        ])
        let b = Region(layer: 1, polygons: [
            makeTriangle(x1: 200, y1: 0, x2: 300, y2: 0, x3: 250, y3: 100)
        ])
        let result = a.or(b)
        #expect(result.polygons.count == 2)
    }

    @Test func triangleNot() {
        let big = Region(layer: 1, polygons: [
            makeTriangle(x1: 0, y1: 0, x2: 200, y2: 0, x3: 100, y3: 200)
        ])
        let small = Region(layer: 1, polygons: [
            makeTriangle(x1: 50, y1: 10, x2: 150, y2: 10, x3: 100, y3: 100)
        ])
        let result = big.not(small)
        // Result should exist and have less area than the big triangle
        #expect(!result.isEmpty)
    }

    @Test func manhattanDetection() {
        // Box should be detected as Manhattan
        let box = makeBox(x1: 0, y1: 0, x2: 100, y2: 100)
        #expect(PolygonUtils.isManhattan(box.points))

        // Triangle is not Manhattan
        let tri = makeTriangle(x1: 0, y1: 0, x2: 100, y2: 0, x3: 50, y3: 100)
        #expect(!PolygonUtils.isManhattan(tri.points))
    }

    @Test func manhattanBooleanRegression() {
        // Ensure existing Manhattan tests still work with the new code path
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 50, y1: 0, x2: 150, y2: 100)])
        let andResult = a.and(b)
        #expect(andResult.area == 5000)
        let orResult = a.or(b)
        #expect(orResult.area == 15000)
        let notResult = a.not(b)
        #expect(notResult.area == 5000)
    }
}

// MARK: - PolygonUtils

@Suite("PolygonUtils")
struct PolygonUtilsTests {

    @Test func signedAreaCCW() {
        let pts: [IRPoint] = [
            IRPoint(x: 0, y: 0), IRPoint(x: 100, y: 0),
            IRPoint(x: 100, y: 100), IRPoint(x: 0, y: 100),
            IRPoint(x: 0, y: 0),
        ]
        #expect(PolygonUtils.signedArea(pts) > 0) // CCW = positive
    }

    @Test func signedAreaCW() {
        let pts: [IRPoint] = [
            IRPoint(x: 0, y: 0), IRPoint(x: 0, y: 100),
            IRPoint(x: 100, y: 100), IRPoint(x: 100, y: 0),
            IRPoint(x: 0, y: 0),
        ]
        #expect(PolygonUtils.signedArea(pts) < 0) // CW = negative
    }

    @Test func ensureCCW() {
        var pts: [IRPoint] = [
            IRPoint(x: 0, y: 0), IRPoint(x: 0, y: 100),
            IRPoint(x: 100, y: 100), IRPoint(x: 100, y: 0),
            IRPoint(x: 0, y: 0),
        ]
        PolygonUtils.ensureCCW(&pts)
        #expect(PolygonUtils.signedArea(pts) > 0)
    }

    @Test func pointInPolygon() {
        let square: [IRPoint] = [
            IRPoint(x: 0, y: 0), IRPoint(x: 100, y: 0),
            IRPoint(x: 100, y: 100), IRPoint(x: 0, y: 100),
            IRPoint(x: 0, y: 0),
        ]
        #expect(PolygonUtils.pointInPolygon(IRPoint(x: 50, y: 50), polygon: square))
        #expect(!PolygonUtils.pointInPolygon(IRPoint(x: 150, y: 50), polygon: square))
    }

    @Test func segmentIntersection() {
        let p1 = IRPoint(x: 0, y: 0), p2 = IRPoint(x: 100, y: 100)
        let p3 = IRPoint(x: 100, y: 0), p4 = IRPoint(x: 0, y: 100)
        let inter = PolygonUtils.segmentIntersection(p1, p2, p3, p4)
        #expect(inter != nil)
        #expect(inter!.x == 50)
        #expect(inter!.y == 50)
    }

    @Test func noSegmentIntersection() {
        let p1 = IRPoint(x: 0, y: 0), p2 = IRPoint(x: 50, y: 0)
        let p3 = IRPoint(x: 0, y: 10), p4 = IRPoint(x: 50, y: 10)
        let inter = PolygonUtils.segmentIntersection(p1, p2, p3, p4)
        #expect(inter == nil)
    }

    @Test func edges() {
        let pts: [IRPoint] = [
            IRPoint(x: 0, y: 0), IRPoint(x: 100, y: 0),
            IRPoint(x: 100, y: 100), IRPoint(x: 0, y: 0),
        ]
        let edges = PolygonUtils.edges(of: pts)
        #expect(edges.count == 3)
    }

    @Test func segmentDistance() {
        let dist = PolygonUtils.segmentDistance(
            IRPoint(x: 0, y: 0), IRPoint(x: 100, y: 0),
            IRPoint(x: 0, y: 50), IRPoint(x: 100, y: 50)
        )
        #expect(abs(dist - 50.0) < 0.01)
    }
}

// MARK: - Sizing with CornerMode

@Suite("Sizing with CornerMode")
struct SizingCornerModeTests {

    @Test func squareCorner() {
        let r = Region(layer: 1, polygons: [makeBox(x1: 10, y1: 10, x2: 90, y2: 90)])
        let grown = r.sized(by: 10, cornerMode: .square)
        #expect(grown.area == 10000) // 100 * 100
    }

    @Test func octagonalCorner() {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let grown = r.sized(by: 10, cornerMode: .octagonal)
        #expect(!grown.isEmpty)
        // Octagonal corners remove some area compared to square
        #expect(grown.polygons[0].points.count > 5) // More vertices due to chamfer
    }

    @Test func roundCorner() {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let grown = r.sized(by: 10, cornerMode: .round(segments: 4))
        #expect(!grown.isEmpty)
        #expect(grown.polygons[0].points.count > 5) // More vertices due to rounding
    }

    @Test func shrinkSquare() {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let shrunk = r.sized(by: -20, cornerMode: .square)
        #expect(shrunk.area == 3600) // 60 * 60
    }

    @Test func nonManhattanSizing() {
        let tri = makeTriangle(x1: 0, y1: 0, x2: 1000, y2: 0, x3: 500, y3: 1000)
        let r = Region(layer: 1, polygons: [tri])
        let grown = r.sized(by: 10, cornerMode: .square)
        #expect(!grown.isEmpty)
        #expect(grown.area > r.area)
    }
}

// MARK: - Edge-based DRC

@Suite("Edge DRC")
struct EdgeDRCTests {

    @Test func widthCheckWithMetric() {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 30, y2: 100)])
        let euclidean = r.widthViolations(minWidth: 50, metric: .euclidean)
        #expect(!euclidean.isEmpty)
        let square = r.widthViolations(minWidth: 50, metric: .square)
        #expect(!square.isEmpty)
    }

    @Test func spaceCheckWithMetric() {
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 120, y1: 0, x2: 220, y2: 100)])
        let violations = a.spaceViolations(to: b, minSpace: 50, metric: .euclidean)
        #expect(!violations.isEmpty)
    }

    @Test func gridCheck() {
        let r = Region(layer: 1, polygons: [
            IRBoundary(layer: 1, datatype: 0, points: [
                IRPoint(x: 0, y: 0), IRPoint(x: 105, y: 0),
                IRPoint(x: 105, y: 100), IRPoint(x: 0, y: 100),
                IRPoint(x: 0, y: 0),
            ], properties: [])
        ])
        let violations = r.gridViolations(gridX: 10, gridY: 10)
        #expect(!violations.isEmpty) // 105 is not on grid of 10
    }

    @Test func gridCheckPass() {
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let violations = r.gridViolations(gridX: 10, gridY: 10)
        #expect(violations.isEmpty)
    }

    @Test func angleCheck() {
        // Box has only 0 and 90 degree edges
        let r = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let violations = r.angleViolations(allowedAngles: [0, 90])
        #expect(violations.isEmpty)
    }

    @Test func angleCheckFail() {
        // Triangle has 45-degree-ish edges
        let r = Region(layer: 1, polygons: [
            makeTriangle(x1: 0, y1: 0, x2: 100, y2: 0, x3: 50, y3: 100)
        ])
        let violations = r.angleViolations(allowedAngles: [0, 90])
        #expect(!violations.isEmpty)
    }

    @Test func notchCheckManhattan() {
        // L-shaped polygon with a notch
        let lShape = IRBoundary(layer: 1, datatype: 0, points: [
            IRPoint(x: 0, y: 0), IRPoint(x: 100, y: 0),
            IRPoint(x: 100, y: 50), IRPoint(x: 50, y: 50),
            IRPoint(x: 50, y: 100), IRPoint(x: 0, y: 100),
            IRPoint(x: 0, y: 0),
        ], properties: [])
        let r = Region(layer: 1, polygons: [lShape])
        let violations = r.notchViolations(minNotch: 60)
        // The notch between the two facing edges is 50 wide < 60
        #expect(!violations.isEmpty)
    }

    @Test func separationCheck() {
        let a = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 100, y2: 100)])
        let b = Region(layer: 1, polygons: [makeBox(x1: 120, y1: 0, x2: 220, y2: 100)])
        let violations = a.separationViolations(to: b, minSeparation: 50)
        #expect(!violations.isEmpty) // Gap is 20 < 50
    }

    @Test func enclosureWithMetric() {
        let outer = Region(layer: 1, polygons: [makeBox(x1: 0, y1: 0, x2: 200, y2: 200)])
        let inner = Region(layer: 2, polygons: [makeBox(x1: 10, y1: 50, x2: 150, y2: 150)])
        let violations = outer.enclosureViolations(inner: inner, minEnclosure: 50, metric: .euclidean)
        #expect(!violations.isEmpty) // left enclosure = 10 < 50
    }
}

// MARK: - Sutherland-Hodgman Clipping

@Suite("Polygon Clipping")
struct PolygonClippingTests {

    @Test func clipSquareBySquare() {
        let subject = [
            IRPoint(x: 0, y: 0), IRPoint(x: 100, y: 0),
            IRPoint(x: 100, y: 100), IRPoint(x: 0, y: 100),
            IRPoint(x: 0, y: 0),
        ]
        let clip = [
            IRPoint(x: 50, y: 50), IRPoint(x: 150, y: 50),
            IRPoint(x: 150, y: 150), IRPoint(x: 50, y: 150),
            IRPoint(x: 50, y: 50),
        ]
        let result = EdgeProcessor.clipPolygon(subject: subject, clip: clip)
        #expect(result != nil)
        if let pts = result {
            // Should be a square 50..100 x 50..100
            var closed = pts
            PolygonUtils.ensureClosed(&closed)
            let area = PolygonUtils.area(closed)
            #expect(area == 2500)
        }
    }

    @Test func clipNonOverlapping() {
        let subject = [
            IRPoint(x: 0, y: 0), IRPoint(x: 10, y: 0),
            IRPoint(x: 10, y: 10), IRPoint(x: 0, y: 10),
            IRPoint(x: 0, y: 0),
        ]
        let clip = [
            IRPoint(x: 100, y: 100), IRPoint(x: 200, y: 100),
            IRPoint(x: 200, y: 200), IRPoint(x: 100, y: 200),
            IRPoint(x: 100, y: 100),
        ]
        let result = EdgeProcessor.clipPolygon(subject: subject, clip: clip)
        #expect(result == nil)
    }

    @Test func clipTriangleBySquare() {
        let subject = [
            IRPoint(x: 0, y: 0), IRPoint(x: 200, y: 0),
            IRPoint(x: 100, y: 200), IRPoint(x: 0, y: 0),
        ]
        let clip = [
            IRPoint(x: 50, y: 0), IRPoint(x: 150, y: 0),
            IRPoint(x: 150, y: 100), IRPoint(x: 50, y: 100),
            IRPoint(x: 50, y: 0),
        ]
        let result = EdgeProcessor.clipPolygon(subject: subject, clip: clip)
        #expect(result != nil)
        if let pts = result {
            #expect(pts.count >= 3)
            var closed = pts
            PolygonUtils.ensureClosed(&closed)
            #expect(PolygonUtils.area(closed) > 0)
        }
    }
}
