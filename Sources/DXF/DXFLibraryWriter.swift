import Foundation
import LayoutIR

/// Writes an IRLibrary to DXF (Drawing Exchange Format) text format.
public enum DXFLibraryWriter {

    public struct Options: Sendable {
        /// DXF $INSUNITS value (0=unspecified, 1=inches, 2=feet, 4=mm, 5=cm, 6=m, 13=um)
        public var dxfUnits: Int
        /// Optional layer number → name mapping. If nil, layer numbers are used as names.
        public var layerMapping: [Int16: String]?

        public init(dxfUnits: Int = 4, layerMapping: [Int16: String]? = nil) {
            self.dxfUnits = dxfUnits
            self.layerMapping = layerMapping
        }
    }

    public static func write(_ library: IRLibrary, options: Options = .init()) throws -> Data {
        let dbu = library.units.dbuPerMicron
        var lines: [String] = []

        // HEADER section
        writeHeader(to: &lines, units: options.dxfUnits)

        // Collect all layers used
        var layerNames: Set<String> = []
        for cell in library.cells {
            for element in cell.elements {
                let layerNum = elementLayer(element)
                layerNames.insert(resolveLayerName(layerNum, mapping: options.layerMapping))
            }
        }

        // TABLES section (LAYER table)
        writeTables(to: &lines, layers: layerNames.sorted())

        // BLOCKS section
        writeBlocks(to: &lines, cells: library.cells, dbu: dbu, options: options)

        // ENTITIES section (first cell = top cell)
        lines.append("  0")
        lines.append("SECTION")
        lines.append("  2")
        lines.append("ENTITIES")

        if let topCell = library.cells.first {
            for element in topCell.elements {
                writeElement(element, to: &lines, dbu: dbu, options: options)
            }
        }

        lines.append("  0")
        lines.append("ENDSEC")

        // EOF
        lines.append("  0")
        lines.append("EOF")

        let text = lines.joined(separator: "\n") + "\n"
        guard let data = text.data(using: .utf8) else {
            throw DXFError.invalidEncoding
        }
        return data
    }

    // MARK: - Sections

    private static func writeHeader(to lines: inout [String], units: Int) {
        lines.append("  0")
        lines.append("SECTION")
        lines.append("  2")
        lines.append("HEADER")

        // AutoCAD version
        lines.append("  9")
        lines.append("$ACADVER")
        lines.append("  1")
        lines.append("AC1027")  // AutoCAD 2013

        // Units
        lines.append("  9")
        lines.append("$INSUNITS")
        lines.append(" 70")
        lines.append("\(units)")

        lines.append("  0")
        lines.append("ENDSEC")
    }

    private static func writeTables(to lines: inout [String], layers: [String]) {
        lines.append("  0")
        lines.append("SECTION")
        lines.append("  2")
        lines.append("TABLES")

        lines.append("  0")
        lines.append("TABLE")
        lines.append("  2")
        lines.append("LAYER")
        lines.append(" 70")
        lines.append("\(layers.count)")

        for layer in layers {
            lines.append("  0")
            lines.append("LAYER")
            lines.append("  2")
            lines.append(layer)
            lines.append(" 70")
            lines.append("0")  // unfrozen/unlocked
            lines.append(" 62")
            lines.append("7")  // white color
            lines.append("  6")
            lines.append("CONTINUOUS")
        }

        lines.append("  0")
        lines.append("ENDTAB")

        lines.append("  0")
        lines.append("ENDSEC")
    }

    private static func writeBlocks(to lines: inout [String], cells: [IRCell], dbu: Double, options: Options) {
        guard cells.count > 1 else { return }

        lines.append("  0")
        lines.append("SECTION")
        lines.append("  2")
        lines.append("BLOCKS")

        // Skip the first cell (top cell), write the rest as blocks
        for cellIdx in 1..<cells.count {
            let cell = cells[cellIdx]
            lines.append("  0")
            lines.append("BLOCK")
            lines.append("  2")
            lines.append(cell.name)
            lines.append(" 10")
            lines.append("0.0")
            lines.append(" 20")
            lines.append("0.0")
            lines.append(" 30")
            lines.append("0.0")

            for element in cell.elements {
                writeElement(element, to: &lines, dbu: dbu, options: options)
            }

            lines.append("  0")
            lines.append("ENDBLK")
        }

        lines.append("  0")
        lines.append("ENDSEC")
    }

    // MARK: - Element Writers

    private static func writeElement(_ element: IRElement, to lines: inout [String], dbu: Double, options: Options) {
        switch element {
        case .boundary(let b):
            writeBoundary(b, to: &lines, dbu: dbu, options: options)
        case .path(let p):
            writePath(p, to: &lines, dbu: dbu, options: options)
        case .text(let t):
            writeText(t, to: &lines, dbu: dbu, options: options)
        case .cellRef(let ref):
            writeCellRef(ref, to: &lines, dbu: dbu)
        case .arrayRef(let aref):
            writeArrayRef(aref, to: &lines, dbu: dbu)
        }
    }

    private static func writeBoundary(_ b: IRBoundary, to lines: inout [String], dbu: Double, options: Options) {
        var pts = b.points
        // Remove closing point for LWPOLYLINE (it uses flag 1 for closed)
        if pts.count > 1 && pts.first == pts.last {
            pts.removeLast()
        }
        guard pts.count >= 3 else { return }

        let layer = resolveLayerName(b.layer, mapping: options.layerMapping)

        lines.append("  0")
        lines.append("LWPOLYLINE")
        lines.append("  8")
        lines.append(layer)
        lines.append(" 90")
        lines.append("\(pts.count)")
        lines.append(" 70")
        lines.append("1") // closed

        for pt in pts {
            lines.append(" 10")
            lines.append(formatCoord(Double(pt.x) / dbu))
            lines.append(" 20")
            lines.append(formatCoord(Double(pt.y) / dbu))
        }
    }

    private static func writePath(_ p: IRPath, to lines: inout [String], dbu: Double, options: Options) {
        let layer = resolveLayerName(p.layer, mapping: options.layerMapping)

        if p.points.count == 2 {
            // Write as LINE for 2-point paths
            lines.append("  0")
            lines.append("LINE")
            lines.append("  8")
            lines.append(layer)
            lines.append(" 10")
            lines.append(formatCoord(Double(p.points[0].x) / dbu))
            lines.append(" 20")
            lines.append(formatCoord(Double(p.points[0].y) / dbu))
            lines.append(" 11")
            lines.append(formatCoord(Double(p.points[1].x) / dbu))
            lines.append(" 21")
            lines.append(formatCoord(Double(p.points[1].y) / dbu))
        } else {
            // Write as open LWPOLYLINE
            lines.append("  0")
            lines.append("LWPOLYLINE")
            lines.append("  8")
            lines.append(layer)
            lines.append(" 90")
            lines.append("\(p.points.count)")
            lines.append(" 70")
            lines.append("0") // open

            for pt in p.points {
                lines.append(" 10")
                lines.append(formatCoord(Double(pt.x) / dbu))
                lines.append(" 20")
                lines.append(formatCoord(Double(pt.y) / dbu))
            }
        }
    }

    private static func writeText(_ t: IRText, to lines: inout [String], dbu: Double, options: Options) {
        let layer = resolveLayerName(t.layer, mapping: options.layerMapping)
        lines.append("  0")
        lines.append("TEXT")
        lines.append("  8")
        lines.append(layer)
        lines.append(" 10")
        lines.append(formatCoord(Double(t.position.x) / dbu))
        lines.append(" 20")
        lines.append(formatCoord(Double(t.position.y) / dbu))
        lines.append(" 40")
        lines.append("1.0") // text height
        lines.append("  1")
        lines.append(t.string)
    }

    private static func writeCellRef(_ ref: IRCellRef, to lines: inout [String], dbu: Double) {
        lines.append("  0")
        lines.append("INSERT")
        lines.append("  2")
        lines.append(ref.cellName)
        lines.append(" 10")
        lines.append(formatCoord(Double(ref.origin.x) / dbu))
        lines.append(" 20")
        lines.append(formatCoord(Double(ref.origin.y) / dbu))

        writeTransformGroups(ref.transform, to: &lines)
    }

    private static func writeArrayRef(_ aref: IRArrayRef, to lines: inout [String], dbu: Double) {
        lines.append("  0")
        lines.append("INSERT")
        lines.append("  2")
        lines.append(aref.cellName)

        let origin = aref.referencePoints.first ?? IRPoint(x: 0, y: 0)
        lines.append(" 10")
        lines.append(formatCoord(Double(origin.x) / dbu))
        lines.append(" 20")
        lines.append(formatCoord(Double(origin.y) / dbu))

        writeTransformGroups(aref.transform, to: &lines)

        lines.append(" 70")
        lines.append("\(aref.columns)")
        lines.append(" 71")
        lines.append("\(aref.rows)")

        // Column spacing
        if aref.referencePoints.count >= 2 && aref.columns > 0 {
            let colEnd = aref.referencePoints[1]
            let totalColDist = Double(colEnd.x - origin.x) / dbu
            let colSpacing = totalColDist / Double(aref.columns)
            lines.append(" 44")
            lines.append(formatCoord(colSpacing))
        }

        // Row spacing
        if aref.referencePoints.count >= 3 && aref.rows > 0 {
            let rowEnd = aref.referencePoints[2]
            let totalRowDist = Double(rowEnd.y - origin.y) / dbu
            let rowSpacing = totalRowDist / Double(aref.rows)
            lines.append(" 45")
            lines.append(formatCoord(rowSpacing))
        }
    }

    private static func writeTransformGroups(_ transform: IRTransform, to lines: inout [String]) {
        if transform.mirrorX {
            lines.append(" 41")
            lines.append(formatCoord(-transform.magnification))
        } else if abs(transform.magnification - 1.0) > 1e-9 {
            lines.append(" 41")
            lines.append(formatCoord(transform.magnification))
        }

        if abs(transform.magnification - 1.0) > 1e-9 || transform.mirrorX {
            let yScale = transform.magnification
            lines.append(" 42")
            lines.append(formatCoord(yScale))
        }

        if abs(transform.angle) > 1e-9 {
            lines.append(" 50")
            lines.append(formatCoord(transform.angle))
        }
    }

    // MARK: - Helpers

    private static func elementLayer(_ element: IRElement) -> Int16 {
        switch element {
        case .boundary(let b): return b.layer
        case .path(let p): return p.layer
        case .text(let t): return t.layer
        case .cellRef: return 0
        case .arrayRef: return 0
        }
    }

    private static func resolveLayerName(_ layer: Int16, mapping: [Int16: String]?) -> String {
        if let name = mapping?[layer] { return name }
        return "\(layer)"
    }

    private static func formatCoord(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.6f", value)
    }
}
