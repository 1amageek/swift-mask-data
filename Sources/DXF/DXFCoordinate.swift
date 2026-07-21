import Foundation
import LayoutIR

enum DXFCoordinate {
    static func point(
        x: Double,
        y: Double,
        databaseUnitsPerMicrometer: Double,
        entity: String
    ) throws -> IRPoint {
        IRPoint(
            x: try scaled(x, by: databaseUnitsPerMicrometer, entity: entity),
            y: try scaled(y, by: databaseUnitsPerMicrometer, entity: entity)
        )
    }

    static func scaled(
        _ value: Double,
        by databaseUnitsPerMicrometer: Double,
        entity: String
    ) throws -> Int32 {
        try int32(value * databaseUnitsPerMicrometer, entity: entity)
    }

    static func int32(_ value: Double, entity: String) throws -> Int32 {
        let truncated = value.rounded(.towardZero)
        guard value.isFinite,
              truncated >= Double(Int32.min),
              truncated <= Double(Int32.max) else {
            throw DXFError.coordinateOutOfRange(entity: entity, value: String(value))
        }
        return Int32(truncated)
    }

    static func adding(
        _ origin: Int32,
        count: Int,
        spacing: Int32,
        entity: String
    ) throws -> Int32 {
        let offset = Int64(count) * Int64(spacing)
        let result = Int64(origin) + offset
        guard result >= Int64(Int32.min), result <= Int64(Int32.max) else {
            throw DXFError.coordinateOutOfRange(entity: entity, value: String(result))
        }
        return Int32(result)
    }
}
