import Foundation
import LayoutIR

/// Reads a CIF (Caltech Intermediate Form) text file and converts it to an IRLibrary.
public enum CIFLibraryReader {

    public static func read(_ data: Data) throws -> IRLibrary {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CIFError.invalidEncoding
        }

        let commands = CIFTokenizer.tokenize(text)
        var cells: [IRCell] = []
        var currentCellName: String?
        var currentScale: Double = 1.0
        var currentElements: [IRElement] = []
        var currentLayer: Int16 = 0
        var layerTable: [String: Int16] = [:]
        var nextLayerID: Int16 = 1

        commandLoop: for cmd in commands {
            let parts = cmd.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let first = parts.first, !first.isEmpty else { continue }

            let command = first.first!

            switch command {
            case "D":
                if first == "DS" || first.hasPrefix("DS") {
                    // DS n s — define cell n with scale 1/s
                    // DS n a b — define cell n with scale a/b
                    let numbers = parseNumbers(parts)
                    let cellID = numbers.count > 0 ? numbers[0] : 0
                    if numbers.count >= 3 && numbers[2] != 0 {
                        currentScale = Double(numbers[1]) / Double(numbers[2])
                    } else if numbers.count > 1 && numbers[1] != 0 {
                        currentScale = 1.0 / Double(numbers[1])
                    } else {
                        currentScale = 1.0
                    }
                    currentCellName = "CELL_\(cellID)"
                    currentElements = []
                    currentLayer = 0
                } else if first == "DF" || first.hasPrefix("DF") {
                    // DF — end cell definition
                    if let name = currentCellName {
                        cells.append(IRCell(name: name, elements: currentElements))
                        currentCellName = nil
                        currentElements = []
                    }
                }

            case "L":
                // L layername — set current layer
                let layerName = parts.count > 1 ? parts[1] : "0"
                if let existing = layerTable[layerName] {
                    currentLayer = existing
                } else if let num = Int16(layerName) {
                    currentLayer = num
                    layerTable[layerName] = num
                } else {
                    currentLayer = nextLayerID
                    layerTable[layerName] = nextLayerID
                    nextLayerID += 1
                }

            case "B":
                // B length width centerX centerY [dirX dirY]
                let numbers = parseNumbers(parts)
                guard numbers.count >= 4 else { continue }
                let length = Int32(Double(numbers[0]) * currentScale)
                let width = Int32(Double(numbers[1]) * currentScale)
                let cx = Int32(Double(numbers[2]) * currentScale)
                let cy = Int32(Double(numbers[3]) * currentScale)
                let halfL = length / 2
                let halfW = width / 2

                let points: [IRPoint]
                if numbers.count >= 6, !(numbers[4] == 1 && numbers[5] == 0) {
                    // Direction vector present: rotate the box
                    let dx = Double(numbers[4])
                    let dy = Double(numbers[5])
                    let mag = (dx * dx + dy * dy).squareRoot()
                    let ndx = mag > 0 ? dx / mag : 1.0
                    let ndy = mag > 0 ? dy / mag : 0.0
                    // perpendicular: (-ndy, ndx)
                    let hlD = Double(halfL)
                    let hwD = Double(halfW)
                    // corner = center +/- halfL*dir +/- halfW*perp
                    // dir = (ndx, ndy), perp = (-ndy, ndx)
                    let cxD = Double(cx), cyD = Double(cy)
                    let c0 = IRPoint(x: Int32(cxD - hlD*ndx + hwD*ndy), y: Int32(cyD - hlD*ndy - hwD*ndx))
                    let c1 = IRPoint(x: Int32(cxD + hlD*ndx + hwD*ndy), y: Int32(cyD + hlD*ndy - hwD*ndx))
                    let c2 = IRPoint(x: Int32(cxD + hlD*ndx - hwD*ndy), y: Int32(cyD + hlD*ndy + hwD*ndx))
                    let c3 = IRPoint(x: Int32(cxD - hlD*ndx - hwD*ndy), y: Int32(cyD - hlD*ndy + hwD*ndx))
                    points = [c0, c1, c2, c3, c0]
                } else {
                    // Axis-aligned box (default or direction (1,0))
                    points = [
                        IRPoint(x: cx - halfL, y: cy - halfW),
                        IRPoint(x: cx + halfL, y: cy - halfW),
                        IRPoint(x: cx + halfL, y: cy + halfW),
                        IRPoint(x: cx - halfL, y: cy + halfW),
                        IRPoint(x: cx - halfL, y: cy - halfW),
                    ]
                }
                currentElements.append(.boundary(IRBoundary(
                    layer: currentLayer, datatype: 0, points: points, properties: []
                )))

            case "W":
                // W width x1 y1 x2 y2 ...
                let numbers = parseNumbers(parts)
                guard numbers.count >= 5 else { continue }
                let pathWidth = Int32(Double(numbers[0]) * currentScale)
                var points: [IRPoint] = []
                var i = 1
                while i + 1 < numbers.count {
                    let px = Int32(Double(numbers[i]) * currentScale)
                    let py = Int32(Double(numbers[i + 1]) * currentScale)
                    points.append(IRPoint(x: px, y: py))
                    i += 2
                }
                guard points.count >= 2 else { continue }
                currentElements.append(.path(IRPath(
                    layer: currentLayer, datatype: 0,
                    pathType: .flush, width: pathWidth,
                    points: points, properties: []
                )))

            case "P":
                // P x1 y1 x2 y2 ... — polygon (auto-close)
                let numbers = parseNumbers(parts)
                guard numbers.count >= 4 else { continue }
                var points: [IRPoint] = []
                var i = 0
                while i + 1 < numbers.count {
                    let px = Int32(Double(numbers[i]) * currentScale)
                    let py = Int32(Double(numbers[i + 1]) * currentScale)
                    points.append(IRPoint(x: px, y: py))
                    i += 2
                }
                guard points.count >= 3 else { continue }
                // Auto-close
                if points.first != points.last {
                    points.append(points[0])
                }
                currentElements.append(.boundary(IRBoundary(
                    layer: currentLayer, datatype: 0, points: points, properties: []
                )))

            case "C":
                // C n [T dx dy] [M [X|Y]] [R dx dy]
                let (cellRef, _) = parseCellRef(parts, scale: currentScale)
                if let ref = cellRef {
                    currentElements.append(.cellRef(ref))
                }

            case "9":
                // 9 text x y [layer] — text label (extension)
                if parts.count >= 4 {
                    let label = parts[1]
                    let tx = Int32(Double(Int(parts[2]) ?? 0) * currentScale)
                    let ty = Int32(Double(Int(parts[3]) ?? 0) * currentScale)
                    currentElements.append(.text(IRText(
                        layer: currentLayer, texttype: 0,
                        transform: .identity,
                        position: IRPoint(x: tx, y: ty),
                        string: label, properties: []
                    )))
                }

            case "E":
                // End of file — stop processing
                break commandLoop

            default:
                // Unknown command — skip
                break
            }
        }

        // If there's an unterminated cell, add it
        if let name = currentCellName {
            cells.append(IRCell(name: name, elements: currentElements))
        }

        return IRLibrary(name: "CIF", units: .default, cells: cells)
    }

    // MARK: - Helpers

    private static func parseNumbers(_ parts: [String]) -> [Int] {
        parts.compactMap { Int($0) }
    }

    private static func parseCellRef(_ parts: [String], scale: Double) -> (IRCellRef?, Int) {
        // C n [T dx dy] [M X|Y] [R dx dy]
        guard parts.count >= 2 else { return (nil, 0) }
        let cellID = parts[1]
        let cellName = "CELL_\(cellID)"
        var dx: Int32 = 0
        var dy: Int32 = 0
        var mirrorX = false
        var angle = 0.0
        var i = 2

        while i < parts.count {
            switch parts[i] {
            case "T":
                if i + 2 < parts.count {
                    dx = Int32(Double(Int(parts[i + 1]) ?? 0) * scale)
                    dy = Int32(Double(Int(parts[i + 2]) ?? 0) * scale)
                    i += 3
                } else { i += 1 }
            case "M":
                if i + 1 < parts.count {
                    if parts[i + 1] == "X" {
                        // Mirror about X-axis: equivalent to mirrorX + 180° rotation
                        mirrorX = true
                        angle += 180.0
                    } else if parts[i + 1] == "Y" {
                        mirrorX = true
                    }
                    i += 2
                } else {
                    mirrorX = true
                    i += 1
                }
            case "R":
                if i + 2 < parts.count {
                    let rx = Double(Int(parts[i + 1]) ?? 1)
                    let ry = Double(Int(parts[i + 2]) ?? 0)
                    angle += atan2(ry, rx) * 180.0 / .pi
                    i += 3
                } else { i += 1 }
            default:
                i += 1
            }
        }

        let transform = IRTransform(mirrorX: mirrorX, magnification: 1.0, angle: angle)
        let ref = IRCellRef(
            cellName: cellName,
            origin: IRPoint(x: dx, y: dy),
            transform: transform,
            properties: []
        )
        return (ref, 0)
    }
}
