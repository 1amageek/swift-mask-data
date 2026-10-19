import Foundation
import LayoutIR

/// Rotation-only MINSERT grid geometry, independent of block scaling/reflection.
enum DXFArrayGeometry {
    static func rotate(x: Double, y: Double, angle: Double) -> (x: Double, y: Double) {
        switch angle.truncatingRemainder(dividingBy: 360) {
        case 0: return (x, y)
        case 90, -270: return (-y, x)
        case 180, -180: return (-x, -y)
        case 270, -90: return (y, -x)
        default:
            let radians = angle.truncatingRemainder(dividingBy: 360) * .pi / 180
            let cosine = cos(radians), sine = sin(radians)
            return (x * cosine - y * sine, x * sine + y * cosine)
        }
    }

    static func endpoint(origin: IRPoint, spacing: Double, count: Int16,
                         column: Bool, rotation: Double, dbu: Double) throws -> IRPoint {
        let distance = spacing * dbu * Double(count)
        let vector = rotate(x: column ? distance : 0, y: column ? 0 : distance, angle: rotation)
        return IRPoint(x: try DXFCoordinate.int32(Double(origin.x) + vector.x, entity: "INSERT"),
            y: try DXFCoordinate.int32(Double(origin.y) + vector.y, entity: "INSERT"))
    }

    static func spacing(origin: IRPoint, endpoint: IRPoint, count: Int16,
                        column: Bool, rotation: Double, dbu: Double) throws -> Double {
        let dx = Double(Int64(endpoint.x) - Int64(origin.x))
        let dy = Double(Int64(endpoint.y) - Int64(origin.y))
        let local = rotate(x: dx, y: dy, angle: -rotation)
        let cross = column ? local.y : local.x
        // Only floating evaluation noise may disappear; read-back still has to be exact.
        let noise = 8 * max(abs(dx), abs(dy)).ulp
        guard abs(cross) <= noise else {
            throw DXFError.unsupportedTransform(entity: "array INSERT", reason: "Reference vectors do not align with the INSERT rotation.")
        }
        let result = (column ? local.x : local.y) / Double(count) / dbu
        guard result.isFinite,
              try self.endpoint(origin: origin, spacing: result, count: count, column: column,
                  rotation: rotation, dbu: dbu) == endpoint else {
            throw DXFError.invalidGeometry("Array spacing cannot reconstruct the exact source reference point")
        }
        return result
    }
}
