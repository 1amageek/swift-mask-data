import LayoutIR

/// Computes the polygon points for a CTRAPEZOID (compact trapezoid) given its type code,
/// origin (x,y), width (w), and height (h). Returns a 5-point closed polygon.
///
/// OASIS specification Table 7-2 defines 25 implicit trapezoid types (0-24).
/// The width and height parameters define the bounding box.
/// Each type defines a specific shape within that bounding box.
func ctrapezoidPoints(type: Int, x: Int32, y: Int32, w: Int32, h: Int32) throws -> [IRPoint] {
  let baseX = Int64(x)
  let baseY = Int64(y)
  let width = Int64(w)
  let height = Int64(h)

  func point(_ x: Int64, _ y: Int64) throws -> IRPoint {
    guard let px = Int32(exactly: x), let py = Int32(exactly: y) else {
      throw OASISError.numericOverflow(
        context: "ctrapezoid point",
        value: "x=\(x), y=\(y)"
      )
    }
    return IRPoint(x: px, y: py)
  }

  let p: [IRPoint]
  switch type {
  // Horizontal trapezoids (types 0-7)
  case 0:
    // Top left cut: /⎺⎺\
    p = [
      try point(baseX + height, baseY),
      try point(baseX + width, baseY),
      try point(baseX + width, baseY + height),
      try point(baseX, baseY + height),
    ]
  case 1:
    // Top right cut
    p = [
      try point(baseX, baseY),
      try point(baseX + width - height, baseY),
      try point(baseX + width, baseY + height),
      try point(baseX, baseY + height),
    ]
  case 2:
    // Bottom left cut
    p = [
      try point(baseX, baseY),
      try point(baseX + width, baseY),
      try point(baseX + width, baseY + height),
      try point(baseX + height, baseY + height),
    ]
  case 3:
    // Bottom right cut
    p = [
      try point(baseX, baseY),
      try point(baseX + width, baseY),
      try point(baseX + width - height, baseY + height),
      try point(baseX, baseY + height),
    ]
  case 4:
    // Left side cut both
    p = [
      try point(baseX + height, baseY),
      try point(baseX + width, baseY),
      try point(baseX + width, baseY + height),
      try point(baseX, baseY + height / 2),
    ]
  case 5:
    // Right side cut both
    p = [
      try point(baseX, baseY),
      try point(baseX + width - height, baseY),
      try point(baseX + width, baseY + height / 2),
      try point(baseX, baseY + height),
    ]
  case 6:
    // Top left + bottom right cut
    p = [
      try point(baseX + height, baseY),
      try point(baseX + width, baseY),
      try point(baseX + width - height, baseY + height),
      try point(baseX, baseY + height),
    ]
  case 7:
    // Top right + bottom left cut
    p = [
      try point(baseX, baseY),
      try point(baseX + width - height, baseY),
      try point(baseX + width, baseY + height),
      try point(baseX + height, baseY + height),
    ]
  // Vertical trapezoids (types 8-15)
  case 8:
    // Bottom-left cut vertical
    p = [
      try point(baseX, baseY + width),
      try point(baseX, baseY),
      try point(baseX + width, baseY),
      try point(baseX + width, baseY + height),
    ]
  case 9:
    // Top-left cut vertical
    p = [
      try point(baseX, baseY),
      try point(baseX + width, baseY),
      try point(baseX + width, baseY + height),
      try point(baseX, baseY + height - width),
    ]
  case 10:
    // Bottom-right cut vertical
    p = [
      try point(baseX, baseY),
      try point(baseX + width, baseY + width),
      try point(baseX + width, baseY + height),
      try point(baseX, baseY + height),
    ]
  case 11:
    // Top-right cut vertical
    p = [
      try point(baseX, baseY),
      try point(baseX + width, baseY),
      try point(baseX + width, baseY + height - width),
      try point(baseX, baseY + height),
    ]
  case 12:
    // Bottom cut both vertical
    p = [
      try point(baseX, baseY + width),
      try point(baseX + width / 2, baseY),
      try point(baseX + width, baseY + width),
      try point(baseX + width, baseY + height),
      try point(baseX, baseY + height),
    ]
  case 13:
    // Top cut both vertical
    p = [
      try point(baseX, baseY),
      try point(baseX + width, baseY),
      try point(baseX + width, baseY + height - width),
      try point(baseX + width / 2, baseY + height),
      try point(baseX, baseY + height - width),
    ]
  case 14:
    // Bottom-left + top-right vertical
    p = [
      try point(baseX, baseY + width),
      try point(baseX + width, baseY),
      try point(baseX + width, baseY + height - width),
      try point(baseX, baseY + height),
    ]
  case 15:
    // Bottom-right + top-left vertical
    p = [
      try point(baseX, baseY),
      try point(baseX + width, baseY + width),
      try point(baseX + width, baseY + height),
      try point(baseX, baseY + height - width),
    ]
  // Special shapes (types 16-24)
  case 16:
    // Rectangle (degenerate trapezoid)
    p = [
      try point(baseX, baseY),
      try point(baseX + width, baseY),
      try point(baseX + width, baseY + height),
      try point(baseX, baseY + height),
    ]
  case 17:
    // Rectangle: w = h (square)
    p = [
      try point(baseX, baseY),
      try point(baseX + width, baseY),
      try point(baseX + width, baseY + width),
      try point(baseX, baseY + width),
    ]
  case 18:
    // Octagon: horizontal/vertical cuts
    let d = height / 3
    p = [
      try point(baseX + d, baseY),
      try point(baseX + width - d, baseY),
      try point(baseX + width, baseY + d),
      try point(baseX + width, baseY + height - d),
      try point(baseX + width - d, baseY + height),
      try point(baseX + d, baseY + height),
      try point(baseX, baseY + height - d),
      try point(baseX, baseY + d),
    ]
  case 19:
    // Octagon: w=h
    let d = width / 3
    p = [
      try point(baseX + d, baseY),
      try point(baseX + width - d, baseY),
      try point(baseX + width, baseY + d),
      try point(baseX + width, baseY + width - d),
      try point(baseX + width - d, baseY + width),
      try point(baseX + d, baseY + width),
      try point(baseX, baseY + width - d),
      try point(baseX, baseY + d),
    ]
  case 20:
    // Triangle pointing right
    p = [
      try point(baseX, baseY),
      try point(baseX + width, baseY + height / 2),
      try point(baseX, baseY + height),
    ]
  case 21:
    // Triangle pointing left
    p = [
      try point(baseX + width, baseY),
      try point(baseX + width, baseY + height),
      try point(baseX, baseY + height / 2),
    ]
  case 22:
    // Triangle pointing up
    p = [
      try point(baseX, baseY),
      try point(baseX + width, baseY),
      try point(baseX + width / 2, baseY + height),
    ]
  case 23:
    // Triangle pointing down
    p = [
      try point(baseX + width / 2, baseY),
      try point(baseX + width, baseY + height),
      try point(baseX, baseY + height),
    ]
  case 24:
    // Triangle: w=h, pointing right
    p = [
      try point(baseX, baseY),
      try point(baseX + width, baseY + width / 2),
      try point(baseX, baseY + width),
    ]
  default:
    guard let typeCode = UInt64(exactly: type) else {
      throw OASISError.numericOverflow(context: "ctrapezoid type", value: String(type))
    }
    throw OASISError.invalidCTrapezoidType(offset: 0, typeCode: typeCode)
  }

  // Close polygon
  var result = p
  result.append(p[0])
  return result
}
