import LayoutIR

enum LEFCoordinate {
    static func point(
        x: Double,
        y: Double,
        databaseUnitsPerMicrometer: Double,
        context: String,
        rounding: FloatingPointRoundingRule? = nil
    ) throws -> IRPoint {
        IRPoint(
            x: try scaled(x, by: databaseUnitsPerMicrometer, context: "\(context) x", rounding: rounding),
            y: try scaled(y, by: databaseUnitsPerMicrometer, context: "\(context) y", rounding: rounding)
        )
    }

    static func scaled(
        _ value: Double,
        by scale: Double,
        context: String,
        rounding: FloatingPointRoundingRule? = nil
    ) throws -> Int32 {
        let scaled = value * scale
        return try int32(rounding.map { scaled.rounded($0) } ?? scaled, context: context)
    }

    static func int32(_ value: Double, context: String) throws -> Int32 {
        guard value.isFinite,
              value >= Double(Int32.min),
              value <= Double(Int32.max) else {
            throw LEFError.coordinateOutOfRange(context: context, value: String(value))
        }
        let integer = value.rounded(.toNearestOrEven)
        // Accept binary multiplication noise, never a genuine sub-DBU vertex.
        guard abs(value - integer) <= value.ulp else {
            throw LEFError.coordinateOffGrid(context: context, value: String(value))
        }
        return Int32(integer)
    }
}
