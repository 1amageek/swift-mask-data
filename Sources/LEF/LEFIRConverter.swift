import Foundation
import CircuiteFoundation
import LayoutIR

/// Converts between LEFDocument and IRLibrary.
public enum LEFIRConverter {

    /// Convert a LEFDocument to an IRLibrary.
    /// Each MACRO becomes an IRCell with boundaries for PIN/OBS geometry.
    public static func toIRLibrary(_ doc: LEFDocument) throws -> IRLibrary {
        let databaseUnitScale = try DatabaseUnitScale(
            databaseUnitsPerMicrometer: doc.dbuPerMicron
        )
        guard doc.layers.count <= Int(Int16.max) else {
            throw LEFError.layerIdentifierOutOfRange(layerCount: doc.layers.count)
        }

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
                    guard let layer = layerMap[port.layerName] else {
                        throw LEFError.unresolvedLayer(port.layerName)
                    }
                    for r in port.rects {
                        let boundary = try rectToBoundary(r, layer: layer, dbu: dbu)
                        elements.append(.boundary(boundary))
                    }
                    for poly in port.polygons {
                        let boundary = try polygonToBoundary(poly, layer: layer, dbu: dbu)
                        elements.append(.boundary(boundary))
                    }
                    if let firstRect = port.rects.first {
                        let center = try LEFCoordinate.point(
                            x: midpoint(firstRect.x1, firstRect.x2),
                            y: midpoint(firstRect.y1, firstRect.y2),
                            databaseUnitsPerMicrometer: dbu,
                            context: "PIN \(pin.name) label"
                        )
                        elements.append(.text(IRText(
                            layer: layer,
                            texttype: 0,
                            transform: .identity,
                            position: center,
                            string: pin.name,
                            properties: []
                        )))
                    } else if let firstPoly = port.polygons.first, !firstPoly.isEmpty {
                        let center = try LEFCoordinate.point(
                            x: try mean(firstPoly.map(\.x), context: "PIN \(pin.name) label x"),
                            y: try mean(firstPoly.map(\.y), context: "PIN \(pin.name) label y"),
                            databaseUnitsPerMicrometer: dbu,
                            context: "PIN \(pin.name) label"
                        )
                        elements.append(.text(IRText(
                            layer: layer,
                            texttype: 0,
                            transform: .identity,
                            position: center,
                            string: pin.name,
                            properties: []
                        )))
                    }
                }
            }

            for obs in macro.obs {
                guard let layer = layerMap[obs.layerName] else {
                    throw LEFError.unresolvedLayer(obs.layerName)
                }
                for r in obs.rects {
                    elements.append(.boundary(try rectToBoundary(r, layer: layer, dbu: dbu)))
                }
                for poly in obs.polygons {
                    elements.append(.boundary(try polygonToBoundary(poly, layer: layer, dbu: dbu)))
                }
            }

            cells.append(IRCell(name: macro.name, elements: elements))
        }

        return IRLibrary(
            name: "LEF",
            databaseUnitScale: databaseUnitScale,
            cells: cells
        )
    }

    /// Convert an IRLibrary to a LEFDocument.
    /// Each IRCell becomes a MACRO. Boundaries become OBS geometry.
    public static func toLEFDocument(_ library: IRLibrary) throws -> LEFDocument {
        let dbu = library.databaseUnitScale.databaseUnitsPerMicrometer
        var macros: [LEFMacroDef] = []
        var usedLayers: Set<Int16> = []

        for cell in library.cells {
            var obs: [LEFPort] = []
            var layerRects: [Int16: [LEFRect]] = [:]

            for element in cell.elements {
                if case .boundary(let b) = element {
                    usedLayers.insert(b.layer)
                    let rect = try boundaryToRect(b, dbu: dbu)
                    layerRects[b.layer, default: []].append(rect)
                }
            }

            for (layer, rects) in layerRects.sorted(by: { $0.key < $1.key }) {
                obs.append(LEFPort(layerName: "LAYER_\(layer)", rects: rects))
            }

            macros.append(LEFMacroDef(name: cell.name, obs: obs))
        }

        let layers = usedLayers.sorted().map {
            LEFLayerDef(name: "LAYER_\($0)", type: .routing)
        }
        return LEFDocument(dbuPerMicron: dbu, layers: layers, macros: macros)
    }

    // MARK: - Helpers

    private static func rectToBoundary(_ r: LEFRect, layer: Int16, dbu: Double) throws -> IRBoundary {
        let minimum = try LEFCoordinate.point(
            x: r.x1,
            y: r.y1,
            databaseUnitsPerMicrometer: dbu,
            context: "RECT minimum"
        )
        let maximum = try LEFCoordinate.point(
            x: r.x2,
            y: r.y2,
            databaseUnitsPerMicrometer: dbu,
            context: "RECT maximum"
        )
        return IRBoundary(layer: layer, datatype: 0, points: [
            minimum,
            IRPoint(x: maximum.x, y: minimum.y),
            maximum,
            IRPoint(x: minimum.x, y: maximum.y),
            minimum,
        ], properties: [])
    }

    private static func polygonToBoundary(
        _ polygon: [LEFPoint],
        layer: Int16,
        dbu: Double
    ) throws -> IRBoundary {
        var points = try polygon.map {
            try LEFCoordinate.point(
                x: $0.x,
                y: $0.y,
                databaseUnitsPerMicrometer: dbu,
                context: "POLYGON"
            )
        }
        if let first = points.first, points.last != first {
            points.append(first)
        }
        return IRBoundary(layer: layer, datatype: 0, points: points, properties: [])
    }

    private static func boundaryToRect(_ b: IRBoundary, dbu: Double) throws -> LEFRect {
        let xs = b.points.map(\.x)
        let ys = b.points.map(\.y)
        guard let minimumX = xs.min(), let minimumY = ys.min(),
              let maximumX = xs.max(), let maximumY = ys.max() else {
            throw LEFError.invalidGeometry("boundary has no points")
        }
        let minX = Double(minimumX) / dbu
        let minY = Double(minimumY) / dbu
        let maxX = Double(maximumX) / dbu
        let maxY = Double(maximumY) / dbu
        return LEFRect(x1: minX, y1: minY, x2: maxX, y2: maxY)
    }

    private static func midpoint(_ first: Double, _ second: Double) -> Double {
        first / 2.0 + second / 2.0
    }

    private static func mean(_ values: [Double], context: String) throws -> Double {
        guard !values.isEmpty else {
            throw LEFError.invalidGeometry("\(context) has no coordinates")
        }
        guard values.allSatisfy(\.isFinite) else {
            throw LEFError.coordinateOutOfRange(context: context, value: "non-finite")
        }
        let scale = values.map { abs($0) }.max() ?? 0
        guard scale > 0 else { return 0 }
        let count = Double(values.count)
        return values.reduce(0) { partial, value in
            partial + value / scale / count
        } * scale
    }
}
