import LayoutIR

/// Computes the polygon points for a CTRAPEZOID (compact trapezoid) given its type code,
/// origin (x,y), width (w), and height (h). Returns a 5-point closed polygon.
///
/// OASIS specification Table 7-2 defines 25 implicit trapezoid types (0-24).
/// The width and height parameters define the bounding box.
/// Each type defines a specific shape within that bounding box.
func ctrapezoidPoints(type: Int, x: Int32, y: Int32, w: Int32, h: Int32) throws -> [IRPoint] {
    let p: [IRPoint]
    switch type {
    // Horizontal trapezoids (types 0-7)
    case 0:
        // Top left cut: /⎺⎺\
        p = [
            IRPoint(x: x + h, y: y),
            IRPoint(x: x + w, y: y),
            IRPoint(x: x + w, y: y + h),
            IRPoint(x: x, y: y + h),
        ]
    case 1:
        // Top right cut
        p = [
            IRPoint(x: x, y: y),
            IRPoint(x: x + w - h, y: y),
            IRPoint(x: x + w, y: y + h),
            IRPoint(x: x, y: y + h),
        ]
    case 2:
        // Bottom left cut
        p = [
            IRPoint(x: x, y: y),
            IRPoint(x: x + w, y: y),
            IRPoint(x: x + w, y: y + h),
            IRPoint(x: x + h, y: y + h),
        ]
    case 3:
        // Bottom right cut
        p = [
            IRPoint(x: x, y: y),
            IRPoint(x: x + w, y: y),
            IRPoint(x: x + w - h, y: y + h),
            IRPoint(x: x, y: y + h),
        ]
    case 4:
        // Left side cut both
        p = [
            IRPoint(x: x + h, y: y),
            IRPoint(x: x + w, y: y),
            IRPoint(x: x + w, y: y + h),
            IRPoint(x: x, y: y + h / 2),
        ]
    case 5:
        // Right side cut both
        p = [
            IRPoint(x: x, y: y),
            IRPoint(x: x + w - h, y: y),
            IRPoint(x: x + w, y: y + h / 2),
            IRPoint(x: x, y: y + h),
        ]
    case 6:
        // Top left + bottom right cut
        p = [
            IRPoint(x: x + h, y: y),
            IRPoint(x: x + w, y: y),
            IRPoint(x: x + w - h, y: y + h),
            IRPoint(x: x, y: y + h),
        ]
    case 7:
        // Top right + bottom left cut
        p = [
            IRPoint(x: x, y: y),
            IRPoint(x: x + w - h, y: y),
            IRPoint(x: x + w, y: y + h),
            IRPoint(x: x + h, y: y + h),
        ]
    // Vertical trapezoids (types 8-15)
    case 8:
        // Bottom-left cut vertical
        p = [
            IRPoint(x: x, y: y + w),
            IRPoint(x: x, y: y),
            IRPoint(x: x + w, y: y),
            IRPoint(x: x + w, y: y + h),
        ]
    case 9:
        // Top-left cut vertical
        p = [
            IRPoint(x: x, y: y),
            IRPoint(x: x + w, y: y),
            IRPoint(x: x + w, y: y + h),
            IRPoint(x: x, y: y + h - w),
        ]
    case 10:
        // Bottom-right cut vertical
        p = [
            IRPoint(x: x, y: y),
            IRPoint(x: x + w, y: y + w),
            IRPoint(x: x + w, y: y + h),
            IRPoint(x: x, y: y + h),
        ]
    case 11:
        // Top-right cut vertical
        p = [
            IRPoint(x: x, y: y),
            IRPoint(x: x + w, y: y),
            IRPoint(x: x + w, y: y + h - w),
            IRPoint(x: x, y: y + h),
        ]
    case 12:
        // Bottom cut both vertical
        p = [
            IRPoint(x: x, y: y + w),
            IRPoint(x: x + w / 2, y: y),
            IRPoint(x: x + w, y: y + w),
            IRPoint(x: x + w, y: y + h),
            IRPoint(x: x, y: y + h),
        ]
    case 13:
        // Top cut both vertical
        p = [
            IRPoint(x: x, y: y),
            IRPoint(x: x + w, y: y),
            IRPoint(x: x + w, y: y + h - w),
            IRPoint(x: x + w / 2, y: y + h),
            IRPoint(x: x, y: y + h - w),
        ]
    case 14:
        // Bottom-left + top-right vertical
        p = [
            IRPoint(x: x, y: y + w),
            IRPoint(x: x + w, y: y),
            IRPoint(x: x + w, y: y + h - w),
            IRPoint(x: x, y: y + h),
        ]
    case 15:
        // Bottom-right + top-left vertical
        p = [
            IRPoint(x: x, y: y),
            IRPoint(x: x + w, y: y + w),
            IRPoint(x: x + w, y: y + h),
            IRPoint(x: x, y: y + h - w),
        ]
    // Special shapes (types 16-24)
    case 16:
        // Rectangle (degenerate trapezoid)
        p = [
            IRPoint(x: x, y: y),
            IRPoint(x: x + w, y: y),
            IRPoint(x: x + w, y: y + h),
            IRPoint(x: x, y: y + h),
        ]
    case 17:
        // Rectangle: w = h (square)
        p = [
            IRPoint(x: x, y: y),
            IRPoint(x: x + w, y: y),
            IRPoint(x: x + w, y: y + w),
            IRPoint(x: x, y: y + w),
        ]
    case 18:
        // Octagon: horizontal/vertical cuts
        let d = h / 3
        p = [
            IRPoint(x: x + d, y: y),
            IRPoint(x: x + w - d, y: y),
            IRPoint(x: x + w, y: y + d),
            IRPoint(x: x + w, y: y + h - d),
            IRPoint(x: x + w - d, y: y + h),
            IRPoint(x: x + d, y: y + h),
            IRPoint(x: x, y: y + h - d),
            IRPoint(x: x, y: y + d),
        ]
    case 19:
        // Octagon: w=h
        let d = w / 3
        p = [
            IRPoint(x: x + d, y: y),
            IRPoint(x: x + w - d, y: y),
            IRPoint(x: x + w, y: y + d),
            IRPoint(x: x + w, y: y + w - d),
            IRPoint(x: x + w - d, y: y + w),
            IRPoint(x: x + d, y: y + w),
            IRPoint(x: x, y: y + w - d),
            IRPoint(x: x, y: y + d),
        ]
    case 20:
        // Triangle pointing right
        p = [
            IRPoint(x: x, y: y),
            IRPoint(x: x + w, y: y + h / 2),
            IRPoint(x: x, y: y + h),
        ]
    case 21:
        // Triangle pointing left
        p = [
            IRPoint(x: x + w, y: y),
            IRPoint(x: x + w, y: y + h),
            IRPoint(x: x, y: y + h / 2),
        ]
    case 22:
        // Triangle pointing up
        p = [
            IRPoint(x: x, y: y),
            IRPoint(x: x + w, y: y),
            IRPoint(x: x + w / 2, y: y + h),
        ]
    case 23:
        // Triangle pointing down
        p = [
            IRPoint(x: x + w / 2, y: y),
            IRPoint(x: x + w, y: y + h),
            IRPoint(x: x, y: y + h),
        ]
    case 24:
        // Triangle: w=h, pointing right
        p = [
            IRPoint(x: x, y: y),
            IRPoint(x: x + w, y: y + w / 2),
            IRPoint(x: x, y: y + w),
        ]
    default:
        throw OASISError.invalidCTrapezoidType(offset: 0, typeCode: UInt64(type))
    }

    // Close polygon
    var result = p
    result.append(p[0])
    return result
}
