import Foundation
import CircuiteFoundation
import LayoutIR

/// Reads a DXF (Drawing Exchange Format) file and converts it to an IRLibrary.
public enum DXFLibraryReader {

    /// Options for controlling DXF reading behavior.
    public struct Options: Sendable {
        /// Number of line segments used to approximate arcs and circles.
        public var circleSegments: Int
        /// Database-unit scale used for coordinate conversion.
        public var databaseUnitScale: DatabaseUnitScale
        /// Optional layer name → (layer, datatype) mapping.
        public var layerMapping: [String: (layer: Int16, datatype: Int16)]?

        public init(
            circleSegments: Int = 64,
            databaseUnitScale: DatabaseUnitScale,
            layerMapping: [String: (layer: Int16, datatype: Int16)]? = nil
        ) {
            self.circleSegments = circleSegments
            self.databaseUnitScale = databaseUnitScale
            self.layerMapping = layerMapping
        }
    }

    public static func read(
        _ data: Data,
        databaseUnitScale: DatabaseUnitScale
    ) throws -> IRLibrary {
        try read(data, options: Options(databaseUnitScale: databaseUnitScale))
    }

    public static func read(_ data: Data, options: Options) throws -> IRLibrary {
        guard let text = String(data: data, encoding: .utf8) else {
            throw DXFError.invalidEncoding
        }

        let groups = try DXFGroupReader.read(text)
        try DXFStrictValidator.validate(
            groups,
            circleSegments: options.circleSegments,
            databaseUnitsPerMicrometer: options.databaseUnitScale.databaseUnitsPerMicrometer
        )
        let dbu = options.databaseUnitScale.databaseUnitsPerMicrometer
        let segments = options.circleSegments

        var cells: [IRCell] = []
        var topElements: [IRElement] = []
        var blockElements: [IRElement] = []
        var blockName: String?
        var layerMap: [String: Int16] = [:]
        var nextLayerID: Int16 = 1
        var inBlock = false

        // Pre-populate layer map from options
        if let mapping = options.layerMapping {
            for (name, value) in mapping {
                layerMap[name] = value.layer
            }
        }

        var i = 0
        while i < groups.count {
            let g = groups[i]

            // Track section boundaries
            if g.code == 0 && g.value == "SECTION" {
                i += 2 // Skip section type group
                continue
            }
            if g.code == 0 && g.value == "ENDSEC" {
                i += 1
                continue
            }

            // BLOCK / ENDBLK
            if g.code == 0 && g.value == "BLOCK" {
                inBlock = true
                blockElements = []
                blockName = nil
                i += 1
                // Read block properties
                while i < groups.count && groups[i].code != 0 {
                    if groups[i].code == 2 { blockName = groups[i].value }
                    i += 1
                }
                continue
            }
            if g.code == 0 && g.value == "ENDBLK" {
                if let name = blockName {
                    cells.append(IRCell(name: name, elements: blockElements))
                }
                inBlock = false
                blockName = nil
                i += 1
                continue
            }

            if g.code == 0 && g.value == "EOF" { break }

            // POLYLINE (old-style): collect VERTEX entities until SEQEND
            if g.code == 0 && g.value == "POLYLINE" {
                i += 1
                var polylineProps: [DXFGroup] = []
                while i < groups.count && groups[i].code != 0 {
                    polylineProps.append(groups[i])
                    i += 1
                }
                let layer = resolveLayer(polylineProps, layerMap: &layerMap, nextID: &nextLayerID)
                let closed: Bool
                if let closedGroup = polylineProps.first(where: { $0.code == 70 }) {
                    closed = try validatedInt(closedGroup.value) & 1 != 0
                } else {
                    closed = false
                }

                var vertices: [(x: Double, y: Double, bulge: Double)] = []
                while i < groups.count {
                    if groups[i].code == 0 && groups[i].value == "VERTEX" {
                        i += 1
                        var vx = 0.0, vy = 0.0, vbulge = 0.0
                        while i < groups.count && groups[i].code != 0 {
                            switch groups[i].code {
                            case 10: vx = try validatedDouble(groups[i].value)
                            case 20: vy = try validatedDouble(groups[i].value)
                            case 42: vbulge = try validatedDouble(groups[i].value)
                            default: break
                            }
                            i += 1
                        }
                        vertices.append((vx, vy, vbulge))
                    } else if groups[i].code == 0 && groups[i].value == "SEQEND" {
                        i += 1
                        // Skip SEQEND properties
                        while i < groups.count && groups[i].code != 0 { i += 1 }
                        break
                    } else {
                        break
                    }
                }

                let element = try buildPolylineFromVertices(
                    vertices,
                    closed: closed,
                    layer: layer,
                    dbu: dbu,
                    segments: segments
                )
                if inBlock { blockElements.append(element) } else { topElements.append(element) }
                continue
            }

            // Entity parsing
            if g.code == 0 {
                let entityType = g.value
                i += 1

                // Collect entity properties until next group code 0
                var props: [DXFGroup] = []
                while i < groups.count && groups[i].code != 0 {
                    props.append(groups[i])
                    i += 1
                }

                let layer = resolveLayer(props, layerMap: &layerMap, nextID: &nextLayerID)

                switch entityType {
                case "LINE":
                    if let element = try parseLine(props, layer: layer, dbu: dbu) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "LWPOLYLINE":
                    if let element = try parseLWPolyline(props, layer: layer, dbu: dbu, segments: segments) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "CIRCLE":
                    if let element = try parseCircle(props, layer: layer, dbu: dbu, segments: segments) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "ARC":
                    if let element = try parseArc(props, layer: layer, dbu: dbu, segments: segments) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "ELLIPSE":
                    if let element = try parseEllipse(props, layer: layer, dbu: dbu, segments: segments) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "SPLINE":
                    if let element = try parseSpline(props, layer: layer, dbu: dbu) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "HATCH":
                    let elements = try parseHatch(props, layer: layer, dbu: dbu, segments: segments)
                    for element in elements {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "TEXT", "MTEXT":
                    if let element = try parseText(props, layer: layer, dbu: dbu) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "ATTDEF":
                    if let element = try parseAttdef(props, layer: layer, dbu: dbu) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "INSERT":
                    if let element = try parseInsert(props, dbu: dbu) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "SOLID":
                    if let element = try parseSolid(props, layer: layer, dbu: dbu) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                default:
                    break
                }
                continue
            }

            i += 1
        }

        if !topElements.isEmpty {
            cells.insert(IRCell(name: "TOP", elements: topElements), at: 0)
        }

        return IRLibrary(
            name: "DXF",
            databaseUnitScale: options.databaseUnitScale,
            cells: cells
        )
    }

    // MARK: - Entity Parsers

    private static func parseLine(_ props: [DXFGroup], layer: Int16, dbu: Double) throws -> IRElement? {
        var x1 = 0.0, y1 = 0.0, x2 = 0.0, y2 = 0.0
        for p in props {
            switch p.code {
            case 10: x1 = try validatedDouble(p.value)
            case 20: y1 = try validatedDouble(p.value)
            case 11: x2 = try validatedDouble(p.value)
            case 21: y2 = try validatedDouble(p.value)
            default: break
            }
        }
        return .path(IRPath(
            layer: layer, datatype: 0,
            pathType: .flush, width: 0,
            points: [
                try DXFCoordinate.point(x: x1, y: y1, databaseUnitsPerMicrometer: dbu, entity: "LINE"),
                try DXFCoordinate.point(x: x2, y: y2, databaseUnitsPerMicrometer: dbu, entity: "LINE"),
            ],
            properties: []
        ))
    }

    private static func parseLWPolyline(
        _ props: [DXFGroup],
        layer: Int16,
        dbu: Double,
        segments: Int
    ) throws -> IRElement? {
        var xs: [Double] = []
        var ys: [Double] = []
        var bulges: [Double] = []
        var closed = false

        for p in props {
            switch p.code {
            case 10:
                xs.append(try validatedDouble(p.value))
                // Ensure bulge array stays in sync: each vertex gets a bulge
                if bulges.count < xs.count - 1 {
                    bulges.append(0)
                }
            case 20: ys.append(try validatedDouble(p.value))
            case 42: bulges.append(try validatedDouble(p.value))
            case 70: closed = (try validatedInt(p.value)) & 1 != 0
            default: break
            }
        }

        // Pad bulges to match vertex count
        while bulges.count < xs.count {
            bulges.append(0)
        }

        let count = min(xs.count, ys.count)
        guard count >= 2 else {
            throw DXFError.invalidGeometry("LWPOLYLINE requires at least two complete vertices")
        }

        let hasBulge = bulges.contains(where: { $0 != 0 })

        if hasBulge {
            // Build polyline with arc segments
            var vertices: [(x: Double, y: Double, bulge: Double)] = []
            for idx in 0..<count {
                vertices.append((xs[idx], ys[idx], bulges[idx]))
            }
            return try buildPolylineFromVertices(
                vertices,
                closed: closed,
                layer: layer,
                dbu: dbu,
                segments: segments
            )
        }

        var points = try (0..<count).map { idx in
            try DXFCoordinate.point(
                x: xs[idx],
                y: ys[idx],
                databaseUnitsPerMicrometer: dbu,
                entity: "LWPOLYLINE"
            )
        }

        if closed {
            if points.first != points.last {
                points.append(points[0])
            }
            return .boundary(IRBoundary(layer: layer, datatype: 0, points: points, properties: []))
        } else {
            return .path(IRPath(layer: layer, datatype: 0, pathType: .flush, width: 0, points: points, properties: []))
        }
    }

    private static func parseCircle(
        _ props: [DXFGroup],
        layer: Int16,
        dbu: Double,
        segments: Int
    ) throws -> IRElement? {
        var cx = 0.0, cy = 0.0, radius = 0.0
        for p in props {
            switch p.code {
            case 10: cx = try validatedDouble(p.value)
            case 20: cy = try validatedDouble(p.value)
            case 40: radius = try validatedDouble(p.value)
            default: break
            }
        }

        guard radius > 0 else { throw DXFError.invalidGeometry("CIRCLE radius must be positive") }

        let points = try DXFArcGeometry.approximateCircle(cx: cx, cy: cy, radius: radius, segments: segments, dbu: dbu)
        guard points.count >= 3 else { throw DXFError.invalidGeometry("CIRCLE approximation is empty") }
        return .boundary(IRBoundary(layer: layer, datatype: 0, points: points, properties: []))
    }

    private static func parseArc(
        _ props: [DXFGroup],
        layer: Int16,
        dbu: Double,
        segments: Int
    ) throws -> IRElement? {
        var cx = 0.0, cy = 0.0, radius = 0.0
        var startAngle = 0.0, endAngle = 360.0
        for p in props {
            switch p.code {
            case 10: cx = try validatedDouble(p.value)
            case 20: cy = try validatedDouble(p.value)
            case 40: radius = try validatedDouble(p.value)
            case 50: startAngle = try validatedDouble(p.value)
            case 51: endAngle = try validatedDouble(p.value)
            default: break
            }
        }

        guard radius > 0 else { throw DXFError.invalidGeometry("ARC radius must be positive") }

        let points = try DXFArcGeometry.approximateArc(
            cx: cx, cy: cy, radius: radius,
            startAngleDeg: startAngle, endAngleDeg: endAngle,
            segments: segments, dbu: dbu
        )
        guard points.count >= 2 else { throw DXFError.invalidGeometry("ARC approximation is empty") }
        return .path(IRPath(
            layer: layer, datatype: 0,
            pathType: .flush, width: 0,
            points: points, properties: []
        ))
    }

    private static func parseEllipse(
        _ props: [DXFGroup],
        layer: Int16,
        dbu: Double,
        segments: Int
    ) throws -> IRElement? {
        var cx = 0.0, cy = 0.0
        var majorDx = 0.0, majorDy = 0.0
        var ratio = 1.0
        var startParam = 0.0, endParam = 2.0 * .pi

        for p in props {
            switch p.code {
            case 10: cx = try validatedDouble(p.value)
            case 20: cy = try validatedDouble(p.value)
            case 11: majorDx = try validatedDouble(p.value)
            case 21: majorDy = try validatedDouble(p.value)
            case 40: ratio = try validatedDouble(p.value)
            case 41: startParam = try validatedDouble(p.value)
            case 42: endParam = try validatedDouble(p.value)
            default: break
            }
        }

        let majorLen = (majorDx * majorDx + majorDy * majorDy).squareRoot()
        guard majorLen.isFinite, majorLen > 0 else {
            throw DXFError.invalidGeometry("ELLIPSE major axis must be finite and nonzero")
        }

        let points = try DXFArcGeometry.approximateEllipse(
            cx: cx, cy: cy,
            majorDx: majorDx, majorDy: majorDy,
            ratio: ratio,
            startParam: startParam, endParam: endParam,
            segments: segments, dbu: dbu
        )
        guard points.count >= 2 else { throw DXFError.invalidGeometry("ELLIPSE approximation is empty") }

        let sweep = endParam - startParam
        let isFull = abs(sweep - 2.0 * .pi) < 0.001 || abs(sweep) < 0.001
        if isFull {
            return .boundary(IRBoundary(layer: layer, datatype: 0, points: points, properties: []))
        } else {
            return .path(IRPath(layer: layer, datatype: 0, pathType: .flush, width: 0, points: points, properties: []))
        }
    }

    private static func parseSpline(_ props: [DXFGroup], layer: Int16, dbu: Double) throws -> IRElement? {
        // Read fit points (group codes 11/21) and control points (10/20)
        var fitXs: [Double] = []
        var fitYs: [Double] = []
        var ctrlXs: [Double] = []
        var ctrlYs: [Double] = []
        var closed = false

        for p in props {
            switch p.code {
            case 10: ctrlXs.append(try validatedDouble(p.value))
            case 20: ctrlYs.append(try validatedDouble(p.value))
            case 11: fitXs.append(try validatedDouble(p.value))
            case 21: fitYs.append(try validatedDouble(p.value))
            case 70: closed = (try validatedInt(p.value)) & 1 != 0
            default: break
            }
        }

        // Prefer fit points if available (they lie on the curve)
        let xs: [Double]
        let ys: [Double]
        if !fitXs.isEmpty {
            xs = fitXs
            ys = fitYs
        } else {
            xs = ctrlXs
            ys = ctrlYs
        }

        let count = min(xs.count, ys.count)
        guard count >= 2 else { throw DXFError.invalidGeometry("SPLINE requires at least two complete points") }

        var points = try (0..<count).map { idx in
            try DXFCoordinate.point(
                x: xs[idx],
                y: ys[idx],
                databaseUnitsPerMicrometer: dbu,
                entity: "SPLINE"
            )
        }

        if closed {
            if points.first != points.last {
                points.append(points[0])
            }
            guard points.count >= 4 else { throw DXFError.invalidGeometry("closed SPLINE requires at least three distinct points") }
            return .boundary(IRBoundary(layer: layer, datatype: 0, points: points, properties: []))
        } else {
            return .path(IRPath(layer: layer, datatype: 0, pathType: .flush, width: 0, points: points, properties: []))
        }
    }

    private static func parseHatch(
        _ props: [DXFGroup],
        layer: Int16,
        dbu: Double,
        segments: Int
    ) throws -> [IRElement] {
        // HATCH has boundary loops. We extract the boundary path coordinates.
        // Group 91 = number of boundary paths
        // Group 92 = boundary path type (bit flags)
        //   bit 1 = external, bit 2 = polyline
        // For polyline boundary: 72 (hasBulge), 73 (closed), then 10/20/42 vertices
        // For edge boundary: 93 = number of edges, then edge data

        var elements: [IRElement] = []
        var idx = 0

        while idx < props.count {
            // Look for boundary path type marker (group 92)
            if props[idx].code == 92 {
                let pathType = try validatedInt(props[idx].value)
                idx += 1

                if pathType & 2 != 0 {
                    // Polyline boundary
                    var hasBulge = false
                    var isClosed = true
                    var vertices: [(x: Double, y: Double, bulge: Double)] = []

                    while idx < props.count && props[idx].code != 92 && props[idx].code != 75 && props[idx].code != 76 {
                        if props[idx].code == 72 {
                            hasBulge = (try validatedInt(props[idx].value)) != 0
                            idx += 1
                        } else if props[idx].code == 73 {
                            isClosed = (try validatedInt(props[idx].value)) != 0
                            idx += 1
                        } else if props[idx].code == 93 {
                            idx += 1 // number of vertices, just skip
                        } else if props[idx].code == 10 {
                            let vx = try validatedDouble(props[idx].value)
                            idx += 1
                            let vy = idx < props.count && props[idx].code == 20 ? try validatedDouble(props[idx].value) : 0
                            if idx < props.count && props[idx].code == 20 { idx += 1 }
                            var vbulge = 0.0
                            if hasBulge, idx < props.count, props[idx].code == 42 {
                                vbulge = try validatedDouble(props[idx].value)
                                idx += 1
                            }
                            vertices.append((vx, vy, vbulge))
                        } else {
                            idx += 1
                        }
                    }

                    guard vertices.count >= 3 else {
                        throw DXFError.invalidGeometry("HATCH polyline boundary requires at least three vertices")
                    }
                    elements.append(try buildPolylineFromVertices(
                        vertices,
                        closed: isClosed,
                        layer: layer,
                        dbu: dbu,
                        segments: segments
                    ))
                } else {
                    // Edge boundary
                    var edgeCount = 0
                    if idx < props.count && props[idx].code == 93 {
                        edgeCount = try validatedInt(props[idx].value)
                        idx += 1
                    }

                    var points: [IRPoint] = []
                    for _ in 0..<edgeCount {
                        guard idx < props.count, props[idx].code == 72 else { break }
                        let edgeType = try validatedInt(props[idx].value)
                        idx += 1

                        switch edgeType {
                        case 1: // Line
                            var x1 = 0.0, y1 = 0.0, x2 = 0.0, y2 = 0.0
                            while idx < props.count && props[idx].code != 72 && props[idx].code != 92 && props[idx].code != 75 && props[idx].code != 97 {
                                switch props[idx].code {
                                case 10: x1 = try validatedDouble(props[idx].value)
                                case 20: y1 = try validatedDouble(props[idx].value)
                                case 11: x2 = try validatedDouble(props[idx].value)
                                case 21: y2 = try validatedDouble(props[idx].value)
                                default: break
                                }
                                idx += 1
                            }
                            if points.isEmpty {
                                points.append(try DXFCoordinate.point(
                                    x: x1,
                                    y: y1,
                                    databaseUnitsPerMicrometer: dbu,
                                    entity: "HATCH"
                                ))
                            }
                            points.append(try DXFCoordinate.point(
                                x: x2,
                                y: y2,
                                databaseUnitsPerMicrometer: dbu,
                                entity: "HATCH"
                            ))

                        case 2: // Circular arc
                            var cx = 0.0, cy = 0.0, r = 0.0, sa = 0.0, ea = 360.0
                            var isCounterclockwise = true
                            while idx < props.count && props[idx].code != 72 && props[idx].code != 92 && props[idx].code != 75 && props[idx].code != 97 {
                                switch props[idx].code {
                                case 10: cx = try validatedDouble(props[idx].value)
                                case 20: cy = try validatedDouble(props[idx].value)
                                case 40: r = try validatedDouble(props[idx].value)
                                case 50: sa = try validatedDouble(props[idx].value)
                                case 51: ea = try validatedDouble(props[idx].value)
                                case 73: isCounterclockwise = try validatedInt(props[idx].value) != 0
                                default: break
                                }
                                idx += 1
                            }
                            var arcPts = try DXFArcGeometry.approximateArc(
                                cx: cx, cy: cy, radius: r,
                                startAngleDeg: isCounterclockwise ? sa : ea,
                                endAngleDeg: isCounterclockwise ? ea : sa,
                                segments: segments, dbu: dbu
                            )
                            if !isCounterclockwise {
                                arcPts.reverse()
                            }
                            for (ptIdx, pt) in arcPts.enumerated() {
                                if ptIdx == 0 && !points.isEmpty { continue }
                                points.append(pt)
                            }

                        case 3: // Elliptical arc
                            var ecx = 0.0, ecy = 0.0, emx = 0.0, emy = 0.0
                            var eRatio = 1.0, esp = 0.0, eep = 2.0 * .pi
                            var isCounterclockwise = true
                            while idx < props.count && props[idx].code != 72 && props[idx].code != 92 && props[idx].code != 75 && props[idx].code != 97 {
                                switch props[idx].code {
                                case 10: ecx = try validatedDouble(props[idx].value)
                                case 20: ecy = try validatedDouble(props[idx].value)
                                case 11: emx = try validatedDouble(props[idx].value)
                                case 21: emy = try validatedDouble(props[idx].value)
                                case 40: eRatio = try validatedDouble(props[idx].value)
                                case 50: esp = (try validatedDouble(props[idx].value)) / 180.0 * .pi
                                case 51: eep = (try validatedDouble(props[idx].value)) / 180.0 * .pi
                                case 73: isCounterclockwise = try validatedInt(props[idx].value) != 0
                                default: break
                                }
                                idx += 1
                            }
                            var ellPts = try DXFArcGeometry.approximateEllipse(
                                cx: ecx, cy: ecy,
                                majorDx: emx, majorDy: emy,
                                ratio: eRatio,
                                startParam: isCounterclockwise ? esp : eep,
                                endParam: isCounterclockwise ? eep : esp,
                                segments: segments, dbu: dbu
                            )
                            if !isCounterclockwise {
                                ellPts.reverse()
                            }
                            for (ptIdx, pt) in ellPts.enumerated() {
                                if ptIdx == 0 && !points.isEmpty { continue }
                                points.append(pt)
                            }

                        default:
                            throw DXFError.unsupportedEntity("HATCH edge type \(edgeType)")
                        }
                    }

                    guard points.count >= 3 else {
                        throw DXFError.invalidGeometry("HATCH edge boundary requires at least three points")
                    }
                    if points.first != points.last {
                        points.append(points[0])
                    }
                    elements.append(.boundary(IRBoundary(
                        layer: layer, datatype: 0, points: points, properties: []
                    )))
                }
            } else {
                idx += 1
            }
        }

        guard !elements.isEmpty else {
            throw DXFError.invalidGeometry("HATCH contains no representable boundary")
        }
        return elements
    }

    private static func parseText(_ props: [DXFGroup], layer: Int16, dbu: Double) throws -> IRElement? {
        var x = 0.0, y = 0.0, text = ""
        for p in props {
            switch p.code {
            case 10: x = try validatedDouble(p.value)
            case 20: y = try validatedDouble(p.value)
            case 1: text = p.value
            default: break
            }
        }
        guard !text.isEmpty else { return nil }
        return .text(IRText(
            layer: layer, texttype: 0,
            transform: .identity,
            position: try DXFCoordinate.point(
                x: x,
                y: y,
                databaseUnitsPerMicrometer: dbu,
                entity: "TEXT"
            ),
            string: text, properties: []
        ))
    }

    private static func parseAttdef(_ props: [DXFGroup], layer: Int16, dbu: Double) throws -> IRElement? {
        var x = 0.0, y = 0.0, tag = "", defaultVal = ""
        for p in props {
            switch p.code {
            case 10: x = try validatedDouble(p.value)
            case 20: y = try validatedDouble(p.value)
            case 2: tag = p.value
            case 1: defaultVal = p.value
            default: break
            }
        }
        let text = tag.isEmpty ? defaultVal : tag
        guard !text.isEmpty else { return nil }
        return .text(IRText(
            layer: layer, texttype: 0,
            transform: .identity,
            position: try DXFCoordinate.point(
                x: x,
                y: y,
                databaseUnitsPerMicrometer: dbu,
                entity: "ATTDEF"
            ),
            string: text, properties: []
        ))
    }

    private static func parseInsert(_ props: [DXFGroup], dbu: Double) throws -> IRElement? {
        var blockName = "", x = 0.0, y = 0.0
        var scaleX = 1.0, scaleY = 1.0
        var rotation = 0.0
        var cols: Int16 = 1, rows: Int16 = 1
        var colSpacing = 0.0, rowSpacing = 0.0

        for p in props {
            switch p.code {
            case 2: blockName = p.value
            case 10: x = try validatedDouble(p.value)
            case 20: y = try validatedDouble(p.value)
            case 41: scaleX = try validatedDouble(p.value)
            case 42: scaleY = try validatedDouble(p.value)
            case 50: rotation = try validatedDouble(p.value)
            case 70: cols = Int16(try validatedInt(p.value))
            case 71: rows = Int16(try validatedInt(p.value))
            case 44: colSpacing = try validatedDouble(p.value)
            case 45: rowSpacing = try validatedDouble(p.value)
            default: break
            }
        }

        guard !blockName.isEmpty else { return nil }

        let origin = try DXFCoordinate.point(
            x: x,
            y: y,
            databaseUnitsPerMicrometer: dbu,
            entity: "INSERT"
        )

        // Determine if mirrored: negative X scale means mirror
        let mirrorX = scaleX < 0
        let absX = abs(scaleX)
        let absY = abs(scaleY)
        guard scaleY > 0, abs(absX - absY) < 1e-9 else {
            throw DXFError.unsupportedTransform(
                entity: "INSERT",
                reason: "non-uniform or Y-axis mirrored scale"
            )
        }
        let mag = absX
        let isIdentityMag = abs(mag - 1.0) < 1e-9
        let isIdentityRot = abs(rotation) < 1e-9
        let isIdentityScale = isIdentityMag && abs(absY - absX) < 1e-9

        let transform: IRTransform
        if mirrorX || !isIdentityRot || !isIdentityScale {
            transform = IRTransform(
                mirrorX: mirrorX,
                magnification: isIdentityMag ? 1.0 : mag,
                angle: rotation
            )
        } else {
            transform = .identity
        }

        // Array insert
        if cols > 1 || rows > 1 {
            let colDist = try DXFCoordinate.scaled(colSpacing, by: dbu, entity: "INSERT")
            let rowDist = try DXFCoordinate.scaled(rowSpacing, by: dbu, entity: "INSERT")
            // Reference points: [origin, col-end, row-end]
            let colEnd = IRPoint(
                x: try DXFCoordinate.adding(origin.x, count: Int(cols), spacing: colDist, entity: "INSERT"),
                y: origin.y
            )
            let rowEnd = IRPoint(
                x: origin.x,
                y: try DXFCoordinate.adding(origin.y, count: Int(rows), spacing: rowDist, entity: "INSERT")
            )
            return .arrayRef(IRArrayRef(
                cellName: blockName,
                transform: transform,
                columns: cols,
                rows: rows,
                referencePoints: [origin, colEnd, rowEnd],
                properties: []
            ))
        }

        return .cellRef(IRCellRef(
            cellName: blockName,
            origin: origin,
            transform: transform,
            properties: []
        ))
    }

    private static func parseSolid(_ props: [DXFGroup], layer: Int16, dbu: Double) throws -> IRElement? {
        // SOLID has 3 or 4 corner points: (10,20), (11,21), (12,22), (13,23)
        var x0 = 0.0, y0 = 0.0, x1 = 0.0, y1 = 0.0
        var x2 = 0.0, y2 = 0.0, x3 = 0.0, y3 = 0.0
        var hasP3 = false

        for p in props {
            switch p.code {
            case 10: x0 = try validatedDouble(p.value)
            case 20: y0 = try validatedDouble(p.value)
            case 11: x1 = try validatedDouble(p.value)
            case 21: y1 = try validatedDouble(p.value)
            case 12: x2 = try validatedDouble(p.value)
            case 22: y2 = try validatedDouble(p.value)
            case 13: x3 = try validatedDouble(p.value); hasP3 = true
            case 23: y3 = try validatedDouble(p.value)
            default: break
            }
        }

        // DXF SOLID vertex order: 0, 1, 3, 2 (note: swapped 2 and 3)
        var points = [
            try DXFCoordinate.point(x: x0, y: y0, databaseUnitsPerMicrometer: dbu, entity: "SOLID"),
            try DXFCoordinate.point(x: x1, y: y1, databaseUnitsPerMicrometer: dbu, entity: "SOLID"),
            try DXFCoordinate.point(x: x3, y: y3, databaseUnitsPerMicrometer: dbu, entity: "SOLID"),
            try DXFCoordinate.point(x: x2, y: y2, databaseUnitsPerMicrometer: dbu, entity: "SOLID"),
        ]

        // If point 3 == point 2, it's a triangle
        if !hasP3 || (x3 == x2 && y3 == y2) {
            points = [
                try DXFCoordinate.point(x: x0, y: y0, databaseUnitsPerMicrometer: dbu, entity: "SOLID"),
                try DXFCoordinate.point(x: x1, y: y1, databaseUnitsPerMicrometer: dbu, entity: "SOLID"),
                try DXFCoordinate.point(x: x2, y: y2, databaseUnitsPerMicrometer: dbu, entity: "SOLID"),
            ]
        }

        points.append(points[0]) // close
        return .boundary(IRBoundary(layer: layer, datatype: 0, points: points, properties: []))
    }

    // MARK: - Polyline Builder (with bulge support)

    private static func buildPolylineFromVertices(
        _ vertices: [(x: Double, y: Double, bulge: Double)],
        closed: Bool,
        layer: Int16,
        dbu: Double,
        segments: Int
    ) throws -> IRElement {
        guard vertices.count >= 2 else {
            throw DXFError.invalidGeometry("POLYLINE requires at least two complete vertices")
        }

        var points: [IRPoint] = []
        let totalVertices = closed ? vertices.count : vertices.count - 1

        for idx in 0..<totalVertices {
            let v = vertices[idx]
            points.append(try DXFCoordinate.point(
                x: v.x,
                y: v.y,
                databaseUnitsPerMicrometer: dbu,
                entity: "POLYLINE"
            ))

            if v.bulge != 0 {
                let nextIdx = (idx + 1) % vertices.count
                let next = vertices[nextIdx]
                let arcPts = try DXFArcGeometry.bulgeToArcPoints(
                    from: (v.x, v.y),
                    to: (next.x, next.y),
                    bulge: v.bulge,
                    segments: max(segments / 4, 8),
                    dbu: dbu
                )
                points.append(contentsOf: arcPts)
            }
        }

        // Add last vertex for open polylines
        if !closed {
            let last = vertices[vertices.count - 1]
            points.append(try DXFCoordinate.point(
                x: last.x,
                y: last.y,
                databaseUnitsPerMicrometer: dbu,
                entity: "POLYLINE"
            ))
        }

        if closed {
            if points.first != points.last {
                points.append(points[0])
            }
            guard points.count >= 4 else {
                throw DXFError.invalidGeometry("closed POLYLINE requires at least three distinct points")
            }
            return .boundary(IRBoundary(layer: layer, datatype: 0, points: points, properties: []))
        } else {
            guard points.count >= 2 else {
                throw DXFError.invalidGeometry("POLYLINE requires at least two points")
            }
            return .path(IRPath(layer: layer, datatype: 0, pathType: .flush, width: 0, points: points, properties: []))
        }
    }

    // MARK: - Helpers

    /// Numeric syntax is checked by DXFStrictValidator before entity parsing.
    private static func validatedDouble(_ value: String) throws -> Double {
        guard let number = Double(value) else {
            throw DXFError.invalidStructure("DXF numeric validation invariant was violated")
        }
        return number
    }

    /// Integer syntax is checked by DXFStrictValidator before entity parsing.
    private static func validatedInt(_ value: String) throws -> Int {
        guard let number = Int(value) else {
            throw DXFError.invalidStructure("DXF integer validation invariant was violated")
        }
        return number
    }

    private static func resolveLayer(_ props: [DXFGroup], layerMap: inout [String: Int16], nextID: inout Int16) -> Int16 {
        for p in props {
            if p.code == 8 {
                let name = p.value
                if let existing = layerMap[name] { return existing }
                if let num = Int16(name) {
                    layerMap[name] = num
                    return num
                }
                let id = nextID
                layerMap[name] = id
                nextID += 1
                return id
            }
        }
        return 0
    }
}
