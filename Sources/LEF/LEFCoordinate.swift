import LayoutIR

enum LEFCoordinate {
    static func point(
        x: Double,
        y: Double,
        databaseUnitsPerMicrometer: Double,
        context: String
    ) throws -> IRPoint {
        IRPoint(
            x: try scaled(x, by: databaseUnitsPerMicrometer, context: "\(context) x"),
            y: try scaled(y, by: databaseUnitsPerMicrometer, context: "\(context) y")
        )
    }

    static func scaled(_ value: Double, by scale: Double, context: String) throws -> Int32 {
        try int32(value * scale, context: context)
    }

    static func int32(_ value: Double, context: String) throws -> Int32 {
        let truncated = value.rounded(.towardZero)
        guard truncated.isFinite,
              truncated >= Double(Int32.min),
              truncated <= Double(Int32.max) else {
            throw LEFError.coordinateOutOfRange(context: context, value: String(value))
        }
        return Int32(truncated)
    }
}
