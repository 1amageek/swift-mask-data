import Foundation
import LayoutIR

/// Reads a DXF (Drawing Exchange Format) file and converts it to an IRLibrary.
public enum DXFLibraryReader {

    /// Options for controlling DXF reading behavior.
    public struct Options: Sendable {
        /// Number of line segments used to approximate arcs and circles.
        public var circleSegments: Int
        /// Units for coordinate conversion.
        public var units: IRUnits
        /// Optional layer name → (layer, datatype) mapping.
        public var layerMapping: [String: (layer: Int16, datatype: Int16)]?

        public init(
            circleSegments: Int = 64,
            units: IRUnits = .default,
            layerMapping: [String: (layer: Int16, datatype: Int16)]? = nil
        ) {
            self.circleSegments = circleSegments
            self.units = units
            self.layerMapping = layerMapping
        }
    }

    public static func read(_ data: Data, units: IRUnits = .default) throws -> IRLibrary {
        try read(data, options: Options(units: units))
    }

    public static func read(_ data: Data, options: Options) throws -> IRLibrary {
        guard let text = String(data: data, encoding: .utf8) else {
            throw DXFError.invalidEncoding
        }

        let groups = DXFGroupReader.read(text)
        let dbu = options.units.dbuPerMicron
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
                let closed = polylineProps.first(where: { $0.code == 70 }).flatMap { (Int($0.value) ?? 0) & 1 != 0 } ?? false

                var vertices: [(x: Double, y: Double, bulge: Double)] = []
                while i < groups.count {
                    if groups[i].code == 0 && groups[i].value == "VERTEX" {
                        i += 1
                        var vx = 0.0, vy = 0.0, vbulge = 0.0
                        while i < groups.count && groups[i].code != 0 {
                            switch groups[i].code {
                            case 10: vx = Double(groups[i].value) ?? 0
                            case 20: vy = Double(groups[i].value) ?? 0
                            case 42: vbulge = Double(groups[i].value) ?? 0
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

                if let element = buildPolylineFromVertices(vertices, closed: closed, layer: layer, dbu: dbu, segments: segments) {
                    if inBlock { blockElements.append(element) } else { topElements.append(element) }
                }
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
                    if let element = parseLine(props, layer: layer, dbu: dbu) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "LWPOLYLINE":
                    if let element = parseLWPolyline(props, layer: layer, dbu: dbu, segments: segments) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "CIRCLE":
                    if let element = parseCircle(props, layer: layer, dbu: dbu, segments: segments) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "ARC":
                    if let element = parseArc(props, layer: layer, dbu: dbu, segments: segments) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "ELLIPSE":
                    if let element = parseEllipse(props, layer: layer, dbu: dbu, segments: segments) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "SPLINE":
                    if let element = parseSpline(props, layer: layer, dbu: dbu) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "HATCH":
                    let elements = parseHatch(props, layer: layer, dbu: dbu, segments: segments)
                    for element in elements {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "TEXT", "MTEXT":
                    if let element = parseText(props, layer: layer, dbu: dbu) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "ATTDEF":
                    if let element = parseAttdef(props, layer: layer, dbu: dbu) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "INSERT":
                    if let element = parseInsert(props, dbu: dbu) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "SOLID":
                    if let element = parseSolid(props, layer: layer, dbu: dbu) {
                        if inBlock { blockElements.append(element) } else { topElements.append(element) }
                    }

                case "POINT":
                    break // No geometry representation

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

        return IRLibrary(name: "DXF", units: options.units, cells: cells)
    }

    // MARK: - Entity Parsers

    private static func parseLine(_ props: [DXFGroup], layer: Int16, dbu: Double) -> IRElement? {
        var x1 = 0.0, y1 = 0.0, x2 = 0.0, y2 = 0.0
        for p in props {
            switch p.code {
            case 10: x1 = Double(p.value) ?? 0
            case 20: y1 = Double(p.value) ?? 0
            case 11: x2 = Double(p.value) ?? 0
            case 21: y2 = Double(p.value) ?? 0
            default: break
            }
        }
        return .path(IRPath(
            layer: layer, datatype: 0,
            pathType: .flush, width: 0,
            points: [
                IRPoint(x: Int32(x1 * dbu), y: Int32(y1 * dbu)),
                IRPoint(x: Int32(x2 * dbu), y: Int32(y2 * dbu)),
            ],
            properties: []
        ))
    }

    private static func parseLWPolyline(_ props: [DXFGroup], layer: Int16, dbu: Double, segments: Int) -> IRElement? {
        var xs: [Double] = []
        var ys: [Double] = []
        var bulges: [Double] = []
        var closed = false

        for p in props {
            switch p.code {
            case 10:
                xs.append(Double(p.value) ?? 0)
                // Ensure bulge array stays in sync: each vertex gets a bulge
                if bulges.count < xs.count - 1 {
                    bulges.append(0)
                }
            case 20: ys.append(Double(p.value) ?? 0)
            case 42: bulges.append(Double(p.value) ?? 0)
            case 70: closed = (Int(p.value) ?? 0) & 1 != 0
            default: break
            }
        }

        // Pad bulges to match vertex count
        while bulges.count < xs.count {
            bulges.append(0)
        }

        let count = min(xs.count, ys.count)
        guard count >= 2 else { return nil }

        let hasBulge = bulges.contains(where: { $0 != 0 })

        if hasBulge {
            // Build polyline with arc segments
            var vertices: [(x: Double, y: Double, bulge: Double)] = []
            for idx in 0..<count {
                vertices.append((xs[idx], ys[idx], bulges[idx]))
            }
            return buildPolylineFromVertices(vertices, closed: closed, layer: layer, dbu: dbu, segments: segments)
        }

        var points = (0..<count).map { idx in
            IRPoint(x: Int32(xs[idx] * dbu), y: Int32(ys[idx] * dbu))
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

    private static func parseCircle(_ props: [DXFGroup], layer: Int16, dbu: Double, segments: Int) -> IRElement? {
        var cx = 0.0, cy = 0.0, radius = 0.0
        for p in props {
            switch p.code {
            case 10: cx = Double(p.value) ?? 0
            case 20: cy = Double(p.value) ?? 0
            case 40: radius = Double(p.value) ?? 0
            default: break
            }
        }

        guard radius > 0 else { return nil }

        let points = DXFArcUtils.approximateCircle(cx: cx, cy: cy, radius: radius, segments: segments, dbu: dbu)
        guard points.count >= 3 else { return nil }
        return .boundary(IRBoundary(layer: layer, datatype: 0, points: points, properties: []))
    }

    private static func parseArc(_ props: [DXFGroup], layer: Int16, dbu: Double, segments: Int) -> IRElement? {
        var cx = 0.0, cy = 0.0, radius = 0.0
        var startAngle = 0.0, endAngle = 360.0
        for p in props {
            switch p.code {
            case 10: cx = Double(p.value) ?? 0
            case 20: cy = Double(p.value) ?? 0
            case 40: radius = Double(p.value) ?? 0
            case 50: startAngle = Double(p.value) ?? 0
            case 51: endAngle = Double(p.value) ?? 360
            default: break
            }
        }

        guard radius > 0 else { return nil }

        let points = DXFArcUtils.approximateArc(
            cx: cx, cy: cy, radius: radius,
            startAngleDeg: startAngle, endAngleDeg: endAngle,
            segments: segments, dbu: dbu
        )
        guard points.count >= 2 else { return nil }
        return .path(IRPath(
            layer: layer, datatype: 0,
            pathType: .flush, width: 0,
            points: points, properties: []
        ))
    }

    private static func parseEllipse(_ props: [DXFGroup], layer: Int16, dbu: Double, segments: Int) -> IRElement? {
        var cx = 0.0, cy = 0.0
        var majorDx = 0.0, majorDy = 0.0
        var ratio = 1.0
        var startParam = 0.0, endParam = 2.0 * .pi

        for p in props {
            switch p.code {
            case 10: cx = Double(p.value) ?? 0
            case 20: cy = Double(p.value) ?? 0
            case 11: majorDx = Double(p.value) ?? 0
            case 21: majorDy = Double(p.value) ?? 0
            case 40: ratio = Double(p.value) ?? 1
            case 41: startParam = Double(p.value) ?? 0
            case 42: endParam = Double(p.value) ?? (2.0 * .pi)
            default: break
            }
        }

        let majorLen = (majorDx * majorDx + majorDy * majorDy).squareRoot()
        guard majorLen > 0 else { return nil }

        let points = DXFArcUtils.approximateEllipse(
            cx: cx, cy: cy,
            majorDx: majorDx, majorDy: majorDy,
            ratio: ratio,
            startParam: startParam, endParam: endParam,
            segments: segments, dbu: dbu
        )
        guard points.count >= 2 else { return nil }

        let sweep = endParam - startParam
        let isFull = abs(sweep - 2.0 * .pi) < 0.001 || abs(sweep) < 0.001
        if isFull {
            return .boundary(IRBoundary(layer: layer, datatype: 0, points: points, properties: []))
        } else {
            return .path(IRPath(layer: layer, datatype: 0, pathType: .flush, width: 0, points: points, properties: []))
        }
    }

    private static func parseSpline(_ props: [DXFGroup], layer: Int16, dbu: Double) -> IRElement? {
        // Read fit points (group codes 11/21) and control points (10/20)
        var fitXs: [Double] = []
        var fitYs: [Double] = []
        var ctrlXs: [Double] = []
        var ctrlYs: [Double] = []
        var closed = false

        for p in props {
            switch p.code {
            case 10: ctrlXs.append(Double(p.value) ?? 0)
            case 20: ctrlYs.append(Double(p.value) ?? 0)
            case 11: fitXs.append(Double(p.value) ?? 0)
            case 21: fitYs.append(Double(p.value) ?? 0)
            case 70: closed = (Int(p.value) ?? 0) & 1 != 0
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
        guard count >= 2 else { return nil }

        var points = (0..<count).map { idx in
            IRPoint(x: Int32(xs[idx] * dbu), y: Int32(ys[idx] * dbu))
        }

        if closed {
            if points.first != points.last {
                points.append(points[0])
            }
            guard points.count >= 4 else { return nil }
            return .boundary(IRBoundary(layer: layer, datatype: 0, points: points, properties: []))
        } else {
            return .path(IRPath(layer: layer, datatype: 0, pathType: .flush, width: 0, points: points, properties: []))
        }
    }

    private static func parseHatch(_ props: [DXFGroup], layer: Int16, dbu: Double, segments: Int) -> [IRElement] {
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
                let pathType = Int(props[idx].value) ?? 0
                idx += 1

                if pathType & 2 != 0 {
                    // Polyline boundary
                    var hasBulge = false
                    var isClosed = true
                    var vertices: [(x: Double, y: Double, bulge: Double)] = []

                    while idx < props.count && props[idx].code != 92 && props[idx].code != 75 && props[idx].code != 76 {
                        if props[idx].code == 72 {
                            hasBulge = (Int(props[idx].value) ?? 0) != 0
                            idx += 1
                        } else if props[idx].code == 73 {
                            isClosed = (Int(props[idx].value) ?? 0) != 0
                            idx += 1
                        } else if props[idx].code == 93 {
                            idx += 1 // number of vertices, just skip
                        } else if props[idx].code == 10 {
                            let vx = Double(props[idx].value) ?? 0
                            idx += 1
                            let vy = idx < props.count && props[idx].code == 20 ? Double(props[idx].value) ?? 0 : 0
                            if idx < props.count && props[idx].code == 20 { idx += 1 }
                            var vbulge = 0.0
                            if hasBulge, idx < props.count, props[idx].code == 42 {
                                vbulge = Double(props[idx].value) ?? 0
                                idx += 1
                            }
                            vertices.append((vx, vy, vbulge))
                        } else {
                            idx += 1
                        }
                    }

                    if vertices.count >= 3 {
                        if let elem = buildPolylineFromVertices(vertices, closed: isClosed, layer: layer, dbu: dbu, segments: segments) {
                            elements.append(elem)
                        }
                    }
                } else {
                    // Edge boundary
                    var edgeCount = 0
                    if idx < props.count && props[idx].code == 93 {
                        edgeCount = Int(props[idx].value) ?? 0
                        idx += 1
                    }

                    var points: [IRPoint] = []
                    for _ in 0..<edgeCount {
                        guard idx < props.count, props[idx].code == 72 else { break }
                        let edgeType = Int(props[idx].value) ?? 0
                        idx += 1

                        switch edgeType {
                        case 1: // Line
                            var x1 = 0.0, y1 = 0.0, x2 = 0.0, y2 = 0.0
                            while idx < props.count && props[idx].code != 72 && props[idx].code != 92 && props[idx].code != 75 && props[idx].code != 97 {
                                switch props[idx].code {
                                case 10: x1 = Double(props[idx].value) ?? 0
                                case 20: y1 = Double(props[idx].value) ?? 0
                                case 11: x2 = Double(props[idx].value) ?? 0
                                case 21: y2 = Double(props[idx].value) ?? 0
                                default: break
                                }
                                idx += 1
                            }
                            if points.isEmpty {
                                points.append(IRPoint(x: Int32(x1 * dbu), y: Int32(y1 * dbu)))
                            }
                            points.append(IRPoint(x: Int32(x2 * dbu), y: Int32(y2 * dbu)))

                        case 2: // Circular arc
                            var cx = 0.0, cy = 0.0, r = 0.0, sa = 0.0, ea = 360.0
                            while idx < props.count && props[idx].code != 72 && props[idx].code != 92 && props[idx].code != 75 && props[idx].code != 97 {
                                switch props[idx].code {
                                case 10: cx = Double(props[idx].value) ?? 0
                                case 20: cy = Double(props[idx].value) ?? 0
                                case 40: r = Double(props[idx].value) ?? 0
                                case 50: sa = Double(props[idx].value) ?? 0
                                case 51: ea = Double(props[idx].value) ?? 360
                                default: break
                                }
                                idx += 1
                            }
                            let arcPts = DXFArcUtils.approximateArc(
                                cx: cx, cy: cy, radius: r,
                                startAngleDeg: sa, endAngleDeg: ea,
                                segments: segments, dbu: dbu
                            )
                            for (ptIdx, pt) in arcPts.enumerated() {
                                if ptIdx == 0 && !points.isEmpty { continue }
                                points.append(pt)
                            }

                        case 3: // Elliptical arc
                            var ecx = 0.0, ecy = 0.0, emx = 0.0, emy = 0.0
                            var eRatio = 1.0, esp = 0.0, eep = 2.0 * .pi
                            while idx < props.count && props[idx].code != 72 && props[idx].code != 92 && props[idx].code != 75 && props[idx].code != 97 {
                                switch props[idx].code {
                                case 10: ecx = Double(props[idx].value) ?? 0
                                case 20: ecy = Double(props[idx].value) ?? 0
                                case 11: emx = Double(props[idx].value) ?? 0
                                case 21: emy = Double(props[idx].value) ?? 0
                                case 40: eRatio = Double(props[idx].value) ?? 1
                                case 50: esp = (Double(props[idx].value) ?? 0) * .pi / 180.0
                                case 51: eep = (Double(props[idx].value) ?? 360.0) * .pi / 180.0
                                default: break
                                }
                                idx += 1
                            }
                            let ellPts = DXFArcUtils.approximateEllipse(
                                cx: ecx, cy: ecy,
                                majorDx: emx, majorDy: emy,
                                ratio: eRatio,
                                startParam: esp, endParam: eep,
                                segments: segments, dbu: dbu
                            )
                            for (ptIdx, pt) in ellPts.enumerated() {
                                if ptIdx == 0 && !points.isEmpty { continue }
                                points.append(pt)
                            }

                        default:
                            // Skip unknown edge type
                            while idx < props.count && props[idx].code != 72 && props[idx].code != 92 && props[idx].code != 75 && props[idx].code != 97 {
                                idx += 1
                            }
                        }
                    }

                    if points.count >= 3 {
                        if points.first != points.last {
                            points.append(points[0])
                        }
                        elements.append(.boundary(IRBoundary(
                            layer: layer, datatype: 0, points: points, properties: []
                        )))
                    }
                }
            } else {
                idx += 1
            }
        }

        return elements
    }

    private static func parseText(_ props: [DXFGroup], layer: Int16, dbu: Double) -> IRElement? {
        var x = 0.0, y = 0.0, text = ""
        for p in props {
            switch p.code {
            case 10: x = Double(p.value) ?? 0
            case 20: y = Double(p.value) ?? 0
            case 1: text = p.value
            default: break
            }
        }
        guard !text.isEmpty else { return nil }
        return .text(IRText(
            layer: layer, texttype: 0,
            transform: .identity,
            position: IRPoint(x: Int32(x * dbu), y: Int32(y * dbu)),
            string: text, properties: []
        ))
    }

    private static func parseAttdef(_ props: [DXFGroup], layer: Int16, dbu: Double) -> IRElement? {
        var x = 0.0, y = 0.0, tag = "", defaultVal = ""
        for p in props {
            switch p.code {
            case 10: x = Double(p.value) ?? 0
            case 20: y = Double(p.value) ?? 0
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
            position: IRPoint(x: Int32(x * dbu), y: Int32(y * dbu)),
            string: text, properties: []
        ))
    }

    private static func parseInsert(_ props: [DXFGroup], dbu: Double) -> IRElement? {
        var blockName = "", x = 0.0, y = 0.0
        var scaleX = 1.0, scaleY = 1.0
        var rotation = 0.0
        var cols: Int16 = 1, rows: Int16 = 1
        var colSpacing = 0.0, rowSpacing = 0.0

        for p in props {
            switch p.code {
            case 2: blockName = p.value
            case 10: x = Double(p.value) ?? 0
            case 20: y = Double(p.value) ?? 0
            case 41: scaleX = Double(p.value) ?? 1
            case 42: scaleY = Double(p.value) ?? 1
            case 50: rotation = Double(p.value) ?? 0
            case 70: cols = Int16(Int(p.value) ?? 1)
            case 71: rows = Int16(Int(p.value) ?? 1)
            case 44: colSpacing = Double(p.value) ?? 0
            case 45: rowSpacing = Double(p.value) ?? 0
            default: break
            }
        }

        guard !blockName.isEmpty else { return nil }

        let origin = IRPoint(x: Int32(x * dbu), y: Int32(y * dbu))

        // Determine if mirrored: negative X scale means mirror
        let mirrorX = scaleX < 0
        let absX = abs(scaleX)
        let absY = abs(scaleY)
        let mag: Double
        if abs(absX - absY) < 1e-9 {
            mag = absX // Uniform scaling
        } else {
            // Non-uniform scaling: IRTransform doesn't support this.
            // Use geometric mean as best approximation.
            mag = (absX * absY).squareRoot()
        }
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
            let colDist = Int32(colSpacing * dbu)
            let rowDist = Int32(rowSpacing * dbu)
            // Reference points: [origin, col-end, row-end]
            let colEnd = IRPoint(x: origin.x + Int32(cols) * colDist, y: origin.y)
            let rowEnd = IRPoint(x: origin.x, y: origin.y + Int32(rows) * rowDist)
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

    private static func parseSolid(_ props: [DXFGroup], layer: Int16, dbu: Double) -> IRElement? {
        // SOLID has 3 or 4 corner points: (10,20), (11,21), (12,22), (13,23)
        var x0 = 0.0, y0 = 0.0, x1 = 0.0, y1 = 0.0
        var x2 = 0.0, y2 = 0.0, x3 = 0.0, y3 = 0.0
        var hasP3 = false

        for p in props {
            switch p.code {
            case 10: x0 = Double(p.value) ?? 0
            case 20: y0 = Double(p.value) ?? 0
            case 11: x1 = Double(p.value) ?? 0
            case 21: y1 = Double(p.value) ?? 0
            case 12: x2 = Double(p.value) ?? 0
            case 22: y2 = Double(p.value) ?? 0
            case 13: x3 = Double(p.value) ?? 0; hasP3 = true
            case 23: y3 = Double(p.value) ?? 0
            default: break
            }
        }

        // DXF SOLID vertex order: 0, 1, 3, 2 (note: swapped 2 and 3)
        var points = [
            IRPoint(x: Int32(x0 * dbu), y: Int32(y0 * dbu)),
            IRPoint(x: Int32(x1 * dbu), y: Int32(y1 * dbu)),
            IRPoint(x: Int32(x3 * dbu), y: Int32(y3 * dbu)),
            IRPoint(x: Int32(x2 * dbu), y: Int32(y2 * dbu)),
        ]

        // If point 3 == point 2, it's a triangle
        if !hasP3 || (x3 == x2 && y3 == y2) {
            points = [
                IRPoint(x: Int32(x0 * dbu), y: Int32(y0 * dbu)),
                IRPoint(x: Int32(x1 * dbu), y: Int32(y1 * dbu)),
                IRPoint(x: Int32(x2 * dbu), y: Int32(y2 * dbu)),
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
    ) -> IRElement? {
        guard vertices.count >= 2 else { return nil }

        var points: [IRPoint] = []
        let totalVertices = closed ? vertices.count : vertices.count - 1

        for idx in 0..<totalVertices {
            let v = vertices[idx]
            points.append(IRPoint(x: Int32(v.x * dbu), y: Int32(v.y * dbu)))

            if v.bulge != 0 {
                let nextIdx = (idx + 1) % vertices.count
                let next = vertices[nextIdx]
                let arcPts = DXFArcUtils.bulgeToArcPoints(
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
            points.append(IRPoint(x: Int32(last.x * dbu), y: Int32(last.y * dbu)))
        }

        if closed {
            if points.first != points.last {
                points.append(points[0])
            }
            guard points.count >= 4 else { return nil }
            return .boundary(IRBoundary(layer: layer, datatype: 0, points: points, properties: []))
        } else {
            guard points.count >= 2 else { return nil }
            return .path(IRPath(layer: layer, datatype: 0, pathType: .flush, width: 0, points: points, properties: []))
        }
    }

    // MARK: - Helpers

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
