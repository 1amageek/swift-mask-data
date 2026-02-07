import Foundation
import LayoutIR

/// Utility functions for arc and circle polygon approximation in DXF.
enum DXFArcUtils {

    /// Approximates a circular arc as a polyline.
    /// - Parameters:
    ///   - cx, cy: Center coordinates
    ///   - radius: Arc radius
    ///   - startAngleDeg: Start angle in degrees (counterclockwise from +X)
    ///   - endAngleDeg: End angle in degrees
    ///   - segments: Number of line segments for the approximation
    ///   - dbu: Database units per micron
    /// - Returns: Array of points along the arc
    static func approximateArc(
        cx: Double, cy: Double,
        radius: Double,
        startAngleDeg: Double, endAngleDeg: Double,
        segments: Int,
        dbu: Double
    ) -> [IRPoint] {
        guard radius > 0, segments > 0 else { return [] }

        let start = startAngleDeg * .pi / 180.0
        var end = endAngleDeg * .pi / 180.0

        // Ensure end > start (counterclockwise sweep)
        while end <= start {
            end += 2.0 * .pi
        }

        let sweep = end - start
        var points: [IRPoint] = []
        for seg in 0...segments {
            let t = Double(seg) / Double(segments)
            let angle = start + t * sweep
            let px = cx + radius * cos(angle)
            let py = cy + radius * sin(angle)
            points.append(IRPoint(x: Int32(px * dbu), y: Int32(py * dbu)))
        }

        return points
    }

    /// Approximates a full circle as a closed polygon.
    static func approximateCircle(
        cx: Double, cy: Double,
        radius: Double,
        segments: Int,
        dbu: Double
    ) -> [IRPoint] {
        guard radius > 0, segments > 0 else { return [] }

        var points: [IRPoint] = []
        for seg in 0...segments {
            let angle = Double(seg) / Double(segments) * 2.0 * .pi
            let px = cx + radius * cos(angle)
            let py = cy + radius * sin(angle)
            points.append(IRPoint(x: Int32(px * dbu), y: Int32(py * dbu)))
        }
        return points
    }

    /// Approximates an elliptical arc as a polyline.
    /// - Parameters:
    ///   - cx, cy: Center coordinates
    ///   - majorDx, majorDy: Major axis endpoint relative to center
    ///   - ratio: Ratio of minor to major axis length
    ///   - startParam: Start parameter (0.0 to 2*pi for full ellipse)
    ///   - endParam: End parameter
    ///   - segments: Number of segments
    ///   - dbu: Database units per micron
    static func approximateEllipse(
        cx: Double, cy: Double,
        majorDx: Double, majorDy: Double,
        ratio: Double,
        startParam: Double, endParam: Double,
        segments: Int,
        dbu: Double
    ) -> [IRPoint] {
        guard segments > 0 else { return [] }

        let majorLen = (majorDx * majorDx + majorDy * majorDy).squareRoot()
        guard majorLen > 0 else { return [] }
        let minorLen = majorLen * ratio

        // Rotation angle of major axis
        let rot = atan2(majorDy, majorDx)
        let cosR = cos(rot)
        let sinR = sin(rot)

        let start = startParam
        var end = endParam
        while end <= start {
            end += 2.0 * .pi
        }

        var points: [IRPoint] = []
        let sweep = end - start
        for seg in 0...segments {
            let t = Double(seg) / Double(segments)
            let param = start + t * sweep
            // Point on unit ellipse
            let ex = majorLen * cos(param)
            let ey = minorLen * sin(param)
            // Rotate and translate
            let px = cx + ex * cosR - ey * sinR
            let py = cy + ex * sinR + ey * cosR
            points.append(IRPoint(x: Int32(px * dbu), y: Int32(py * dbu)))
        }

        return points
    }

    /// Converts a bulge value between two points to arc points.
    /// Bulge = tan(included_angle / 4). Positive = CCW, negative = CW.
    static func bulgeToArcPoints(
        from p1: (x: Double, y: Double),
        to p2: (x: Double, y: Double),
        bulge: Double,
        segments: Int,
        dbu: Double
    ) -> [IRPoint] {
        guard bulge != 0 else { return [] }

        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let chordLen = (dx * dx + dy * dy).squareRoot()
        guard chordLen > 0 else { return [] }

        // Sagitta = |bulge| * chordLen / 2
        let sagitta = abs(bulge) * chordLen / 2.0
        let radius = (chordLen * chordLen / 4.0 + sagitta * sagitta) / (2.0 * sagitta)

        // Midpoint of chord
        let mx = (p1.x + p2.x) / 2.0
        let my = (p1.y + p2.y) / 2.0

        // Perpendicular direction (unit)
        let perpX = -dy / chordLen
        let perpY = dx / chordLen

        // Distance from midpoint to center
        let d = radius - sagitta
        let sign = bulge > 0 ? 1.0 : -1.0

        let cx = mx + sign * d * perpX
        let cy = my + sign * d * perpY

        // Start and end angles
        let startAngle = atan2(p1.y - cy, p1.x - cx)
        let endAngle = atan2(p2.y - cy, p2.x - cx)

        var start = startAngle
        var end = endAngle

        if bulge > 0 {
            // CCW
            while end <= start { end += 2.0 * .pi }
        } else {
            // CW
            while start <= end { start += 2.0 * .pi }
        }

        var points: [IRPoint] = []
        let sweep = end - start
        // Skip first point (it's from the caller) and last point (it's next vertex)
        for seg in 1..<segments {
            let t = Double(seg) / Double(segments)
            let angle = start + t * sweep
            let px = cx + radius * cos(angle)
            let py = cy + radius * sin(angle)
            points.append(IRPoint(x: Int32(px * dbu), y: Int32(py * dbu)))
        }

        return points
    }
}
