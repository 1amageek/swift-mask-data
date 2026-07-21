import Foundation
import LayoutIR

/// Writes an IRLibrary to CIF (Caltech Intermediate Form) text format.
public enum CIFLibraryWriter {

    public struct Options: Sendable {
        public var scaleFactor: Int

        public init(scaleFactor: Int = 1) {
            self.scaleFactor = scaleFactor
        }
    }

    public static func write(_ library: IRLibrary, options: Options = .init()) throws -> Data {
        guard options.scaleFactor > 0 else {
            throw CIFError.invalidOption("scaleFactor must be greater than zero")
        }
        var lines: [String] = []
        var cellNames: Set<String> = []

        for (idx, cell) in library.cells.enumerated() {
            let cellID = idx + 1
            let scaleDivisor = options.scaleFactor
            guard !cell.name.isEmpty,
                  !cell.name.contains(where: { $0.isWhitespace || $0 == ";" || $0 == "(" || $0 == ")" }) else {
                throw CIFError.unsupportedGeometry("cell name")
            }
            guard cellNames.insert(cell.name).inserted else {
                throw CIFError.duplicateCellName(cell.name)
            }
            lines.append("DS \(cellID) \(scaleDivisor);")
            lines.append("9 \(cell.name);")

            var currentLayer: Int16 = -1
            let scale = scaleDivisor

            for element in cell.elements {
                switch element {
                case .boundary(let b):
                    guard b.datatype == 0, b.properties.isEmpty else {
                        throw CIFError.unsupportedGeometry("boundary datatype or properties")
                    }
                    if b.layer != currentLayer {
                        currentLayer = b.layer
                        lines.append("L \(currentLayer);")
                    }
                    try writeBoundary(b, scale: scale, to: &lines)

                case .path(let p):
                    guard p.datatype == 0, p.pathType == .flush, p.properties.isEmpty else {
                        throw CIFError.unsupportedGeometry("path datatype, end style, or properties")
                    }
                    if p.layer != currentLayer {
                        currentLayer = p.layer
                        lines.append("L \(currentLayer);")
                    }
                    try writePath(p, scale: scale, to: &lines)

                case .text(let t):
                    guard t.texttype == 0, t.transform == .identity, t.properties.isEmpty,
                          !t.string.isEmpty,
                          !t.string.contains(where: { $0.isWhitespace || $0 == ";" || $0 == "(" || $0 == ")" }) else {
                        throw CIFError.unsupportedGeometry("text type, transform, properties, or content")
                    }
                    if t.layer != currentLayer {
                        currentLayer = t.layer
                        lines.append("L \(currentLayer);")
                    }
                    let tx = try scaled(t.position.x, by: scale)
                    let ty = try scaled(t.position.y, by: scale)
                    lines.append("9 \(t.string) \(tx) \(ty);")

                case .cellRef(let ref):
                    guard let cellIndex = findCellIndex(ref.cellName, in: library.cells) else {
                        throw CIFError.unresolvedCellReference(ref.cellName)
                    }
                    try writeCellRef(ref, cellIndex: cellIndex, scale: scale, to: &lines)

                case .arrayRef:
                    throw CIFError.unsupportedGeometry("array reference")
                }
            }

            lines.append("DF;")
        }

        lines.append("E")
        lines.append("")

        let text = lines.joined(separator: "\n")
        guard let data = text.data(using: .utf8) else {
            throw CIFError.invalidEncoding
        }
        return data
    }

    // MARK: - Boundary

    private static func writeBoundary(_ b: IRBoundary, scale: Int, to lines: inout [String]) throws {
        var pts = b.points
        // Remove closing point if present
        if pts.count > 1 && pts.first == pts.last {
            pts.removeLast()
        }
        guard pts.count >= 3 else {
            throw CIFError.unsupportedGeometry("boundary with fewer than three vertices")
        }

        // Try to represent as box (B length width cx cy)
        if let box = tryAsBox(pts) {
            lines.append("B \(try scaled(box.length, by: scale)) \(try scaled(box.width, by: scale)) \(try scaled(box.cx, by: scale)) \(try scaled(box.cy, by: scale));")
            return
        }

        // Polygon
        let ptsStr = try pts.map {
            "\(try scaled($0.x, by: scale)) \(try scaled($0.y, by: scale))"
        }.joined(separator: " ")
        lines.append("P \(ptsStr);")
    }

    private struct BoxParams {
        var length: Int64
        var width: Int64
        var cx: Int64
        var cy: Int64
    }

    private static func tryAsBox(_ pts: [IRPoint]) -> BoxParams? {
        guard pts.count == 4 else { return nil }
        let xs = pts.map(\.x)
        let ys = pts.map(\.y)
        guard let minX = xs.min(),
              let maxX = xs.max(),
              let minY = ys.min(),
              let maxY = ys.max() else {
            return nil
        }

        // Check it's actually axis-aligned
        for p in pts {
            if p.x != minX && p.x != maxX { return nil }
            if p.y != minY && p.y != maxY { return nil }
        }
        let expectedCorners = Set([
            IRPoint(x: minX, y: minY),
            IRPoint(x: maxX, y: minY),
            IRPoint(x: maxX, y: maxY),
            IRPoint(x: minX, y: maxY),
        ])
        guard Set(pts) == expectedCorners else {
            return nil
        }

        let length = Int64(maxX) - Int64(minX)
        let width = Int64(maxY) - Int64(minY)
        guard length > 0, width > 0, length.isMultiple(of: 2), width.isMultiple(of: 2) else {
            return nil
        }
        let cx = (Int64(minX) + Int64(maxX)) / 2
        let cy = (Int64(minY) + Int64(maxY)) / 2
        return BoxParams(length: length, width: width, cx: cx, cy: cy)
    }

    // MARK: - Path

    private static func writePath(_ p: IRPath, scale: Int, to lines: inout [String]) throws {
        guard p.points.count >= 2, p.width >= 0 else {
            throw CIFError.unsupportedGeometry("path with invalid width or fewer than two vertices")
        }
        var parts = ["W", "\(try scaled(p.width, by: scale))"]
        for pt in p.points {
            parts.append("\(try scaled(pt.x, by: scale))")
            parts.append("\(try scaled(pt.y, by: scale))")
        }
        lines.append(parts.joined(separator: " ") + ";")
    }

    // MARK: - Cell Reference

    private static func writeCellRef(_ ref: IRCellRef, cellIndex: Int, scale: Int, to lines: inout [String]) throws {
        guard abs(ref.transform.magnification - 1) < 1e-12 else {
            throw CIFError.unsupportedTransform("magnification")
        }
        guard ref.transform.angle.isFinite, ref.properties.isEmpty else {
            throw CIFError.unsupportedTransform("non-finite angle or reference properties")
        }
        var line = "C \(cellIndex)"
        // Transforms
        if ref.transform.mirrorX {
            line += " M Y"
        }

        let angle = ref.transform.angle
        if angle != 0 {
            let normalized = angle.truncatingRemainder(dividingBy: 360)
            let octant = (normalized / 45).rounded()
            guard abs(normalized - octant * 45) < 1e-12 else {
                throw CIFError.unsupportedTransform("rotation must be an exact multiple of 45 degrees")
            }
            let vectors = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
            let index = (Int(octant) % 8 + 8) % 8
            line += " R \(vectors[index].0) \(vectors[index].1)"
        }

        let ox = try scaled(ref.origin.x, by: scale)
        let oy = try scaled(ref.origin.y, by: scale)
        if ox != 0 || oy != 0 {
            line += " T \(ox) \(oy)"
        }

        line += ";"
        lines.append(line)
    }

    private static func findCellIndex(_ name: String, in cells: [IRCell]) -> Int? {
        for (idx, cell) in cells.enumerated() {
            if cell.name == name { return idx + 1 }
        }
        return nil
    }

    private static func scaled(_ value: Int32, by scale: Int) throws -> Int64 {
        try scaled(Int64(value), by: scale)
    }

    private static func scaled(_ value: Int64, by scale: Int) throws -> Int64 {
        let (result, overflow) = value.multipliedReportingOverflow(by: Int64(scale))
        guard !overflow else { throw CIFError.invalidNumber("\(value) * \(scale)") }
        return result
    }
}
