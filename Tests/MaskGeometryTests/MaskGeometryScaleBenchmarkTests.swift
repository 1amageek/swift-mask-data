import Testing
import LayoutIR
@testable import MaskGeometry

/// Wall-clock benchmark of the geometry kernel on synthetic router-scale
/// layouts. Timings are printed for comparison across kernel changes; the
/// assertions only pin result counts so the measured work stays identical.
@Suite("MaskGeometry Scale Benchmark", .serialized, .timeLimit(.minutes(10)))
struct MaskGeometryScaleBenchmarkTests {

    // 1 dbu = 1nm; M1-like rules.
    private static let wireWidth: Int32 = 230
    private static let minSpace: Int32 = 230
    private static let pitch: Int32 = 700
    private static let segmentLength: Int32 = 1000

    /// Router-like wire grid: each row is a run of abutting horizontal
    /// segments (they merge into one feature) with stubs of row/column
    /// dependent height on top. Stub heights vary so scanline rows are
    /// numerous and distinct, as in maze-routed metal.
    private func wireGrid(rows: Int, cols: Int) -> Region {
        var polygons: [IRBoundary] = []
        for r in 0..<rows {
            let yMin = Int32(r) * Self.pitch
            let yMax = yMin + Self.wireWidth
            for c in 0..<cols {
                let xMin = Int32(c) * Self.segmentLength
                polygons.append(box(x1: xMin, y1: yMin, x2: xMin + Self.segmentLength, y2: yMax))
                if (r + c) % 3 == 0 {
                    let stubHeight = Int32(150 + (r * 31 + c * 17) % 50)
                    let stubX = xMin + 200
                    polygons.append(box(
                        x1: stubX, y1: yMax,
                        x2: stubX + Self.wireWidth, y2: yMax + stubHeight
                    ))
                }
            }
        }
        return Region(layer: 1, polygons: polygons)
    }

    /// Via cuts sitting on the stub bases — every cut is fully enclosed by
    /// wire metal with at least 5nm margin missing nowhere except by design.
    private func viaCuts(rows: Int, cols: Int) -> Region {
        var polygons: [IRBoundary] = []
        for r in 0..<rows {
            let yMin = Int32(r) * Self.pitch
            for c in 0..<cols where (r + c) % 3 == 0 {
                let xMin = Int32(c) * Self.segmentLength + 205
                polygons.append(box(
                    x1: xMin, y1: yMin + 5,
                    x2: xMin + 220, y2: yMin + Self.wireWidth - 5
                ))
            }
        }
        return Region(layer: 2, polygons: polygons)
    }

    private func box(x1: Int32, y1: Int32, x2: Int32, y2: Int32) -> IRBoundary {
        IRBoundary(layer: 1, datatype: 0, points: [
            IRPoint(x: x1, y: y1), IRPoint(x: x2, y: y1),
            IRPoint(x: x2, y: y2), IRPoint(x: x1, y: y2),
            IRPoint(x: x1, y: y1),
        ], properties: [])
    }

    private func measure<T>(_ label: String, _ body: () -> T) -> T {
        let clock = ContinuousClock()
        var result: T? = nil
        let duration = clock.measure { result = body() }
        let ms = Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1e15
        print("[bench] \(label): \(String(format: "%.1f", ms))ms")
        return result!
    }

    private func runScale(rows: Int, cols: Int) {
        let wires = wireGrid(rows: rows, cols: cols)
        let cuts = viaCuts(rows: rows, cols: cols)
        let tag = "\(wires.polygons.count)p"

        let merged = measure("merge \(tag)") {
            wires.or(Region(layer: 1))
        }
        #expect(!merged.isEmpty)

        let spacing = measure("selfSpace \(tag)") {
            wires.selfSpaceViolations(minSpace: Self.minSpace)
        }
        #expect(spacing.isEmpty, "synthetic grid is spacing-clean by construction")

        let widths = measure("width \(tag)") {
            wires.widthViolations(minWidth: Self.wireWidth)
        }
        #expect(widths.isEmpty, "synthetic grid is width-clean by construction")

        let enclosure = measure("enclosure \(tag)") {
            wires.enclosureViolations(inner: cuts, minEnclosure: 5)
        }
        #expect(enclosure.isEmpty, "via cuts are enclosed by construction")
    }

    @Test func smallScale() {
        runScale(rows: 60, cols: 60)
    }

    @Test func mediumScale() {
        runScale(rows: 140, cols: 140)
    }
}
