import Foundation
import LayoutIR

/// Converts between LEFDocument and IRLibrary.
public enum LEFIRConverter {

    /// Convert a LEFDocument to an IRLibrary.
    /// Each MACRO becomes an IRCell with boundaries for PIN/OBS geometry.
    public static func toIRLibrary(_ doc: LEFDocument) -> IRLibrary {
        var layerMap: [String: Int16] = [:]
        for (idx, layer) in doc.layers.enumerated() {
            layerMap[layer.name] = Int16(idx + 1)
        }

        let dbu = doc.dbuPerMicron
        var cells: [IRCell] = []

        for macro in doc.macros {
            var elements: [IRElement] = []

            for pin in macro.pins {
                for port in pin.ports {
                    let layer = layerMap[port.layerName] ?? 0
                    for r in port.rects {
                        let boundary = rectToBoundary(r, layer: layer, dbu: dbu)
                        elements.append(.boundary(boundary))
                    }
                    for poly in port.polygons {
                        let boundary = polygonToBoundary(poly, layer: layer, dbu: dbu)
                        elements.append(.boundary(boundary))
                    }
                    if let firstRect = port.rects.first {
                        let cx = Int32((firstRect.x1 + firstRect.x2) / 2.0 * dbu)
                        let cy = Int32((firstRect.y1 + firstRect.y2) / 2.0 * dbu)
                        elements.append(.text(IRText(
                            layer: layer,
                            texttype: 0,
                            transform: .identity,
                            position: IRPoint(x: cx, y: cy),
                            string: pin.name,
                            properties: []
                        )))
                    } else if let firstPoly = port.polygons.first, !firstPoly.isEmpty {
                        let cx = Int32(firstPoly.map(\.x).reduce(0, +) / Double(firstPoly.count) * dbu)
                        let cy = Int32(firstPoly.map(\.y).reduce(0, +) / Double(firstPoly.count) * dbu)
                        elements.append(.text(IRText(
                            layer: layer,
                            texttype: 0,
                            transform: .identity,
                            position: IRPoint(x: cx, y: cy),
                            string: pin.name,
                            properties: []
                        )))
                    }
                }
            }

            for obs in macro.obs {
                let layer = layerMap[obs.layerName] ?? 0
                for r in obs.rects {
                    elements.append(.boundary(rectToBoundary(r, layer: layer, dbu: dbu)))
                }
                for poly in obs.polygons {
                    elements.append(.boundary(polygonToBoundary(poly, layer: layer, dbu: dbu)))
                }
            }

            cells.append(IRCell(name: macro.name, elements: elements))
        }

        return IRLibrary(
            name: "LEF",
            units: IRUnits(dbuPerMicron: dbu),
            cells: cells
        )
    }

    /// Convert an IRLibrary to a LEFDocument.
    /// Each IRCell becomes a MACRO. Boundaries become OBS geometry.
    public static func toLEFDocument(_ library: IRLibrary) -> LEFDocument {
        let dbu = library.units.dbuPerMicron
        var macros: [LEFMacroDef] = []

        for cell in library.cells {
            var obs: [LEFPort] = []
            var layerRects: [Int16: [LEFRect]] = [:]

            for element in cell.elements {
                if case .boundary(let b) = element {
                    let rect = boundaryToRect(b, dbu: dbu)
                    layerRects[b.layer, default: []].append(rect)
                }
            }

            for (layer, rects) in layerRects.sorted(by: { $0.key < $1.key }) {
                obs.append(LEFPort(layerName: "LAYER_\(layer)", rects: rects))
            }

            macros.append(LEFMacroDef(name: cell.name, obs: obs))
        }

        return LEFDocument(dbuPerMicron: dbu, macros: macros)
    }

    // MARK: - Helpers

    private static func rectToBoundary(_ r: LEFRect, layer: Int16, dbu: Double) -> IRBoundary {
        let x1 = Int32(r.x1 * dbu)
        let y1 = Int32(r.y1 * dbu)
        let x2 = Int32(r.x2 * dbu)
        let y2 = Int32(r.y2 * dbu)
        return IRBoundary(layer: layer, datatype: 0, points: [
            IRPoint(x: x1, y: y1),
            IRPoint(x: x2, y: y1),
            IRPoint(x: x2, y: y2),
            IRPoint(x: x1, y: y2),
            IRPoint(x: x1, y: y1),
        ], properties: [])
    }

    private static func polygonToBoundary(_ poly: [LEFPoint], layer: Int16, dbu: Double) -> IRBoundary {
        var points = poly.map { IRPoint(x: Int32($0.x * dbu), y: Int32($0.y * dbu)) }
        if let first = points.first, points.last != first {
            points.append(first)
        }
        return IRBoundary(layer: layer, datatype: 0, points: points, properties: [])
    }

    private static func boundaryToRect(_ b: IRBoundary, dbu: Double) -> LEFRect {
        let xs = b.points.map(\.x)
        let ys = b.points.map(\.y)
        let minX = Double(xs.min() ?? 0) / dbu
        let minY = Double(ys.min() ?? 0) / dbu
        let maxX = Double(xs.max() ?? 0) / dbu
        let maxY = Double(ys.max() ?? 0) / dbu
        return LEFRect(x1: minX, y1: minY, x2: maxX, y2: maxY)
    }
}
