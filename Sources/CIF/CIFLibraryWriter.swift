import Foundation
import LayoutIR

/// Writes an IRLibrary to CIF (Caltech Intermediate Form) text format.
public enum CIFLibraryWriter {

    public struct Options: Sendable {
        public enum WireMode: Sendable {
            case squareEnded
            case flushEnded
            case roundEnded
        }
        public var wireMode: WireMode
        public var scaleFactor: Int

        public init(wireMode: WireMode = .squareEnded, scaleFactor: Int = 1) {
            self.wireMode = wireMode
            self.scaleFactor = scaleFactor
        }
    }

    public static func write(_ library: IRLibrary, options: Options = .init()) throws -> Data {
        var lines: [String] = []

        for (idx, cell) in library.cells.enumerated() {
            let cellID = idx + 1
            let scaleDivisor = options.scaleFactor > 0 ? options.scaleFactor : 1
            lines.append("DS \(cellID) \(scaleDivisor);")

            var currentLayer: Int16 = -1
            let scale = scaleDivisor

            for element in cell.elements {
                switch element {
                case .boundary(let b):
                    if b.layer != currentLayer {
                        currentLayer = b.layer
                        lines.append("L \(currentLayer);")
                    }
                    writeBoundary(b, scale: scale, to: &lines)

                case .path(let p):
                    if p.layer != currentLayer {
                        currentLayer = p.layer
                        lines.append("L \(currentLayer);")
                    }
                    writePath(p, scale: scale, to: &lines)

                case .text(let t):
                    if t.layer != currentLayer {
                        currentLayer = t.layer
                        lines.append("L \(currentLayer);")
                    }
                    let tx = t.position.x * Int32(scale)
                    let ty = t.position.y * Int32(scale)
                    lines.append("9 \(t.string) \(tx) \(ty);")

                case .cellRef(let ref):
                    writeCellRef(ref, cellIndex: findCellIndex(ref.cellName, in: library.cells), scale: scale, to: &lines)

                case .arrayRef:
                    break
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

    private static func writeBoundary(_ b: IRBoundary, scale: Int, to lines: inout [String]) {
        var pts = b.points
        // Remove closing point if present
        if pts.count > 1 && pts.first == pts.last {
            pts.removeLast()
        }

        let s = Int32(scale)

        // Try to represent as box (B length width cx cy)
        if let box = tryAsBox(pts) {
            lines.append("B \(box.length * s) \(box.width * s) \(box.cx * s) \(box.cy * s);")
            return
        }

        // Polygon
        let ptsStr = pts.map { "\($0.x * s) \($0.y * s)" }.joined(separator: " ")
        lines.append("P \(ptsStr);")
    }

    private struct BoxParams {
        var length: Int32
        var width: Int32
        var cx: Int32
        var cy: Int32
    }

    private static func tryAsBox(_ pts: [IRPoint]) -> BoxParams? {
        guard pts.count == 4 else { return nil }
        let xs = pts.map(\.x)
        let ys = pts.map(\.y)
        let minX = xs.min()!
        let maxX = xs.max()!
        let minY = ys.min()!
        let maxY = ys.max()!

        // Check it's actually axis-aligned
        for p in pts {
            if p.x != minX && p.x != maxX { return nil }
            if p.y != minY && p.y != maxY { return nil }
        }

        let length = maxX - minX
        let width = maxY - minY
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        return BoxParams(length: length, width: width, cx: cx, cy: cy)
    }

    // MARK: - Path

    private static func writePath(_ p: IRPath, scale: Int, to lines: inout [String]) {
        let s = Int32(scale)
        var parts = ["W", "\(p.width * s)"]
        for pt in p.points {
            parts.append("\(pt.x * s)")
            parts.append("\(pt.y * s)")
        }
        lines.append(parts.joined(separator: " ") + ";")
    }

    // MARK: - Cell Reference

    private static func writeCellRef(_ ref: IRCellRef, cellIndex: Int, scale: Int, to lines: inout [String]) {
        var line = "C \(cellIndex)"
        let s = Int32(scale)

        // Transforms
        if ref.transform.mirrorX {
            line += " M Y"
        }

        let angle = ref.transform.angle
        if angle != 0 {
            let rad = angle * .pi / 180.0
            let rx = Int(cos(rad) * 1000)
            let ry = Int(sin(rad) * 1000)
            if rx != 1000 || ry != 0 {
                line += " R \(rx) \(ry)"
            }
        }

        let ox = ref.origin.x * s
        let oy = ref.origin.y * s
        if ox != 0 || oy != 0 {
            line += " T \(ox) \(oy)"
        }

        line += ";"
        lines.append(line)
    }

    private static func findCellIndex(_ name: String, in cells: [IRCell]) -> Int {
        for (idx, cell) in cells.enumerated() {
            if cell.name == name { return idx + 1 }
        }
        return 1
    }
}
