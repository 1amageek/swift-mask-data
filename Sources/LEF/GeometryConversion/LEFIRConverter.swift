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
                    try requireResolvedPortGeometry(port)
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
                    for path in port.paths {
                        elements.append(try pathToElement(path, layer: layer, dbu: dbu))
                    }
                    if let firstRect = port.rects.first {
                        let center = try LEFCoordinate.point(
                            x: midpoint(firstRect.x1, firstRect.x2),
                            y: midpoint(firstRect.y1, firstRect.y2),
                            databaseUnitsPerMicrometer: dbu,
                            context: "PIN \(pin.name) label",
                            rounding: .towardZero
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
                            context: "PIN \(pin.name) label",
                            rounding: .towardZero
                        )
                        elements.append(.text(IRText(
                            layer: layer,
                            texttype: 0,
                            transform: .identity,
                            position: center,
                            string: pin.name,
                            properties: []
                        )))
                    } else if let firstPath = port.paths.first, let firstPoint = firstPath.points.first {
                        let position = try LEFCoordinate.point(x: firstPoint.x, y: firstPoint.y,
                            databaseUnitsPerMicrometer: dbu, context: "PIN \(pin.name) label", rounding: .towardZero)
                        elements.append(.text(IRText(layer: layer, position: position, string: pin.name)))
                    }
                }
            }

            for obs in macro.obs {
                try requireResolvedPortGeometry(obs)
                guard let layer = layerMap[obs.layerName] else {
                    throw LEFError.unresolvedLayer(obs.layerName)
                }
                for r in obs.rects {
                    elements.append(.boundary(try rectToBoundary(r, layer: layer, dbu: dbu)))
                }
                for poly in obs.polygons {
                    elements.append(.boundary(try polygonToBoundary(poly, layer: layer, dbu: dbu)))
                }
                for path in obs.paths {
                    elements.append(try pathToElement(path, layer: layer, dbu: dbu))
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
    /// Each IRCell becomes a MACRO with exact supported polygon/path OBS geometry.
    public static func toLEFDocument(_ library: IRLibrary) throws -> LEFDocument {
        guard library.metadata.isEmpty else {
            throw LEFError.invalidGeometry("OBS projection cannot retain library metadata")
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Named via export has no bound master resolver.
        // Production inverse conversion must fail before publishing a document until resolved
        // placement geometry and the explicit via role can be represented without loss.
        for cell in library.cells {
            for element in cell.elements {
                if case .via = element { throw LEFError.invalidGeometry("Named via requires a bound master and role-preserving encoding.") }
            }
        }
        let dbu = library.databaseUnitScale.databaseUnitsPerMicrometer
        var macros: [LEFMacroDef] = []
        var usedLayers: Set<Int16> = []

        for cell in library.cells {
            guard cell.properties.isEmpty else {
                throw LEFError.invalidGeometry("OBS projection cannot retain cell properties")
            }
            var ports: [Int16: LEFPort] = [:]
            for element in cell.elements {
                let layer: Int16
                switch element {
                case .boundary(let boundary):
                    guard boundary.datatype == 0, boundary.properties.isEmpty else {
                        throw LEFError.invalidGeometry("OBS projection cannot retain boundary datatype or properties")
                    }
                    layer = boundary.layer
                    var port = ports[layer] ?? LEFPort(layerName: "LAYER_\(layer)", rects: [])
                    let points = try polygonVertices(boundary)
                    if let rect = rectangle(points, dbu: dbu) {
                        port.rects.append(rect)
                    } else {
                        port.polygons.append(points.map { LEFPoint(x: Double($0.x) / dbu, y: Double($0.y) / dbu) })
                    }
                    ports[layer] = port
                case .path(let path):
                    layer = path.layer
                    var port = ports[layer] ?? LEFPort(layerName: "LAYER_\(layer)", rects: [])
                    try appendPath(path, dbu: dbu, to: &port)
                    ports[layer] = port
                case .text, .cellRef, .arrayRef:
                    // FIXME(INCOMPLETE_IMPLEMENTATION): OBS projection does not own text or hierarchy.
                    // Public inverse calls must refuse until source roles and references can be
                    // retained in LEF rather than discarded or converted into obstruction metal.
                    throw LEFError.invalidGeometry("OBS projection cannot retain text or hierarchy")
                case .via:
                    throw LEFError.invalidGeometry("Named via requires a bound master and role-preserving encoding.")
                }
                usedLayers.insert(layer)
            }
            macros.append(LEFMacroDef(name: cell.name, obs: ports.keys.sorted().compactMap { ports[$0] }))
        }
        let layers = usedLayers.sorted().map { LEFLayerDef(name: "LAYER_\($0)", type: .routing) }
        return LEFDocument(dbuPerMicron: dbu, layers: layers, macros: macros)
    }

    // MARK: - Helpers

    private static func requireResolvedPortGeometry(_ port: LEFPort) throws {
        // FIXME(INCOMPLETE_IMPLEMENTATION): PORT VIA physical projection has no bound master resolver.
        // Public toIRLibrary calls must fail before publishing partial geometry until named
        // placements and their complete source role/master contract can be retained or resolved.
        guard port.vias.isEmpty else {
            throw LEFError.invalidGeometry("PORT VIA projection requires a bound master resolver")
        }
    }

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

    private static func polygonVertices(_ boundary: IRBoundary) throws -> [IRPoint] {
        guard !boundary.points.isEmpty else { throw LEFError.invalidGeometry("boundary has no points") }
        var points = boundary.points
        if points.first == points.last { points.removeLast() }
        guard points.count >= 3, Set(points).count == points.count else {
            throw LEFError.invalidGeometry("POLYGON requires at least three distinct vertices")
        }
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            let dx = Int64(next.x) - Int64(points[index].x)
            let dy = Int64(next.y) - Int64(points[index].y)
            guard dx == 0 || dy == 0 || abs(dx) == abs(dy) else {
                throw LEFError.invalidGeometry("LEF POLYGON edges must be orthogonal or 45 degrees")
            }
        }
        return points
    }

    private static func rectangle(_ points: [IRPoint], dbu: Double) -> LEFRect? {
        guard points.count == 4,
              let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(),
              minX < maxX, minY < maxY,
              points.allSatisfy({ ($0.x == minX || $0.x == maxX) && ($0.y == minY || $0.y == maxY) }),
              points.indices.allSatisfy({ index in
                  let next = points[(index + 1) % 4]
                  return points[index].x == next.x || points[index].y == next.y
              }) else { return nil }
        return LEFRect(x1: Double(minX) / dbu, y1: Double(minY) / dbu,
            x2: Double(maxX) / dbu, y2: Double(maxY) / dbu)
    }

    private static func pathToElement(_ path: LEFPath, layer: Int16, dbu: Double) throws -> IRElement {
        try path.validateGeometry()
        let width = try LEFCoordinate.scaled(path.width, by: dbu, context: "PATH width")
        guard width > 0 else { throw LEFError.invalidGeometry("PATH width must be positive on the source grid") }
        if path.points.count == 1 {
            let point = path.points[0], half = path.width / 2
            return .boundary(try rectToBoundary(LEFRect(x1: point.x - half, y1: point.y - half,
                x2: point.x + half, y2: point.y + half), layer: layer, dbu: dbu))
        }
        let points = try path.points.map { try LEFCoordinate.point(x: $0.x, y: $0.y,
            databaseUnitsPerMicrometer: dbu, context: "PATH") }
        return .path(IRPath(layer: layer, datatype: 0, pathType: .halfWidthExtend, width: width, points: points))
    }

    private static func appendPath(_ path: IRPath, dbu: Double, to port: inout LEFPort) throws {
        guard path.datatype == 0, path.properties.isEmpty, path.width > 0, path.points.count >= 2 else {
            throw LEFError.invalidGeometry("OBS PATH needs positive width, two points and no unrepresented datatype or properties")
        }
        for index in path.points.indices.dropFirst() {
            let first = path.points[index - 1], second = path.points[index]
            guard first != second, first.x == second.x || first.y == second.y else {
                throw LEFError.invalidGeometry("LEF PATH segments must be nonzero and orthogonal")
            }
        }
        if path.pathType != .customExtension, path.beginExtension != nil || path.endExtension != nil {
            throw LEFError.invalidGeometry("Noncustom PATH carries ignored endpoint fields")
        }
        if path.pathType == .halfWidthExtend {
            port.paths.append(LEFPath(width: Double(path.width) / dbu,
                points: path.points.map { LEFPoint(x: Double($0.x) / dbu, y: Double($0.y) / dbu) }))
            return
        }
        guard path.pathType != .round else {
            throw LEFError.invalidGeometry("LEF geometry cannot represent round PATH caps without approximation")
        }
        guard path.width.isMultiple(of: 2) else {
            throw LEFError.invalidGeometry("PATH cap projection requires integral DBU surfaces")
        }
        let half = Int64(path.width / 2)
        let begin: Int64, end: Int64
        if path.pathType == .customExtension {
            guard let first = path.beginExtension, let last = path.endExtension else {
                throw LEFError.invalidGeometry("Custom PATH requires both endpoint extensions")
            }
            begin = Int64(first); end = Int64(last)
        } else {
            begin = 0; end = 0
        }
        for index in 1..<path.points.count {
            let first = path.points[index - 1], last = path.points[index]
            let horizontal = first.y == last.y
            let firstAxis = Int64(horizontal ? first.x : first.y)
            let lastAxis = Int64(horizontal ? last.x : last.y)
            let direction: Int64 = lastAxis > firstAxis ? 1 : -1
            let startExtension = index == 1 ? begin : half
            let endExtension = index == path.points.count - 1 ? end : half
            guard abs(lastAxis - firstAxis) + startExtension + endExtension > 0 else {
                throw LEFError.invalidGeometry("PATH endpoint extensions erase a segment")
            }
            let start = firstAxis - direction * startExtension
            let finish = lastAxis + direction * endExtension
            let cross = Int64(horizontal ? first.y : first.x)
            let x1 = horizontal ? min(start, finish) : cross - half
            let x2 = horizontal ? max(start, finish) : cross + half
            let y1 = horizontal ? cross - half : min(start, finish)
            let y2 = horizontal ? cross + half : max(start, finish)
            guard [x1, x2, y1, y2].allSatisfy({ $0 >= Int64(Int32.min) && $0 <= Int64(Int32.max) }) else {
                throw LEFError.coordinateOutOfRange(context: "PATH cap surface", value: "outside Int32")
            }
            port.rects.append(LEFRect(x1: Double(x1) / dbu, y1: Double(y1) / dbu,
                x2: Double(x2) / dbu, y2: Double(y2) / dbu))
        }
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
