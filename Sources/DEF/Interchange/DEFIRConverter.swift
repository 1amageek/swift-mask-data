import Foundation
import CircuiteFoundation
import LayoutIR

public enum DEFIRConverterError: Error, Equatable, Sendable {
    case unsupportedRouteGeometry(netName: String, layerName: String, reason: String)
    case unrepresentableTransform
    case tooManyLayers(count: Int)
    case missingLayerMapping(layerName: String)
    case invalidLayerNumber(layerName: String, layerNumber: Int16)
    case duplicateMappedLayerNumber(layerName: String, existingLayerName: String, layerNumber: Int16)
    case invalidRouteGeometry(netName: String, layerName: String, reason: String)
}

public struct DEFLayerNumberMapping: Equatable, Sendable {
    private let numbersByName: [String: Int16]

    public init(layerNumbersByName: [String: Int16] = [:]) throws {
        var normalizedNumbers: [String: Int16] = [:]
        for (layerName, layerNumber) in layerNumbersByName {
            guard !layerName.isEmpty else { continue }
            guard layerNumber > 0 else {
                throw DEFIRConverterError.invalidLayerNumber(
                    layerName: layerName,
                    layerNumber: layerNumber
                )
            }
            normalizedNumbers[layerName] = layerNumber
            normalizedNumbers[layerName.lowercased()] = layerNumber
        }
        self.numbersByName = normalizedNumbers
    }

    func number(for layerName: String) throws -> Int16 {
        guard !layerName.isEmpty else { return 0 }
        guard let number = numbersByName[layerName] ?? numbersByName[layerName.lowercased()] else {
            throw DEFIRConverterError.missingLayerMapping(layerName: layerName)
        }
        return number
    }
}

/// Converts between DEFDocument and IRLibrary.
public enum DEFIRConverter {
    private static let componentNamePropertyKey = "def.component.name"
    private static let placementStatusPropertyKey = "def.component.placementStatus"
    private static let pinNamePropertyKey = "def.pin.name"
    private static let pinNetNamePropertyKey = "def.pin.netName"
    private static let pinPlacementStatusPropertyKey = "def.pin.placementStatus"
    private static let netCountPropertyKey = "def.net.count"
    private static let netPropertyPrefix = "def.net"
    private static let specialNetCountPropertyKey = "def.specialNet.count"
    private static let specialNetPropertyPrefix = "def.specialNet"
    private static let pinCountPropertyKey = "def.pin.count"
    private static let pinPropertyPrefix = "def.pin"
    private static let viaDefCountPropertyKey = "def.viaDef.count"
    private static let viaDefPropertyPrefix = "def.viaDef"
    private static let routeKindPropertyKey = "def.route.kind"
    private static let routeNetNamePropertyKey = "def.route.netName"
    private static let routeStatusPropertyKey = "def.route.status"
    private static let routeLayerNamePropertyKey = "def.route.layerName"
    private static let routeWidthPropertyKey = "def.route.width"
    private static let routeShapePropertyKey = "def.route.shape"
    private static let routeSpecialPointsPropertyKey = "def.route.specialPoints"

    /// Convert a DEFDocument to an IRLibrary.
    /// Components become IRCellRef elements in a top-level cell.
    public static func toIRLibrary(_ doc: DEFDocument) throws -> IRLibrary {
        try toIRLibrary(doc, layerNumbers: try DEFLayerNumberMapping())
    }

    /// Convert a DEFDocument to an IRLibrary using an explicit DEF layer-name mapping.
    /// Components become IRCellRef elements in a top-level cell.
    public static func toIRLibrary(
        _ doc: DEFDocument,
        layerNumbers: DEFLayerNumberMapping
    ) throws -> IRLibrary {
        var elements: [IRElement] = []
        var topProperties = documentProperties(doc)
        try validateLayerNumberMapping(layerNumbers, for: doc)

        for comp in doc.components {
            let transform = orientationToTransform(comp.orientation)
            elements.append(.cellRef(IRCellRef(
                cellName: comp.macro,
                origin: IRPoint(x: comp.x, y: comp.y),
                transform: transform,
                properties: componentProperties(comp)
            )))
        }

        // Die area as boundary
        if let area = doc.dieArea {
            let pts: [IRPoint]
            if area.isRectangular, let bb = area.boundingBox {
                pts = [
                    IRPoint(x: bb.x1, y: bb.y1),
                    IRPoint(x: bb.x2, y: bb.y1),
                    IRPoint(x: bb.x2, y: bb.y2),
                    IRPoint(x: bb.x1, y: bb.y2),
                    IRPoint(x: bb.x1, y: bb.y1),
                ]
            } else {
                var polyPts = area.points
                if let first = polyPts.first, polyPts.last != first {
                    polyPts.append(first)
                }
                pts = polyPts
            }
            elements.insert(.boundary(IRBoundary(
                layer: 0, datatype: 0,
                points: pts,
                properties: []
            )), at: 0)
        }

        for net in doc.nets {
            for wire in net.routing {
                let points = try validatedRegularRoutePoints(wire, netName: net.name)
                for index in 1..<points.count {
                    let begin = wire.pointExtensions.isEmpty ? nil : wire.pointExtensions[index - 1]
                    let end = wire.pointExtensions.isEmpty ? nil : wire.pointExtensions[index]
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Mixed implicit/explicit NETS extensions need
                    // an exact preferred LEF WIDTH. DEF import is the production caller; it must fail
                    // until both endpoint distances can be represented without the width placeholder.
                    guard (begin == nil) == (end == nil) else {
                        throw DEFIRConverterError.unsupportedRouteGeometry(
                            netName: net.name, layerName: wire.layerName,
                            reason: "Mixed implicit and explicit extensions require the exact preferred LEF WIDTH.")
                    }
                    var part = wire
                    part.points = [points[index - 1], points[index]]
                    part.viaName = nil
                    elements.append(.path(IRPath(
                        layer: try layerNumbers.number(for: wire.layerName), datatype: 0,
                        pathType: begin == nil ? .halfWidthExtend : .customExtension,
                        width: 1, points: part.points,
                        properties: regularRouteProperties(net: net, wire: part),
                        beginExtension: begin, endExtension: end)))
                }
                if let name = wire.viaName, let origin = points.last {
                    var provenance = wire
                    provenance.viaName = nil
                    elements.append(.via(IRVia(viaName: name, origin: origin,
                        transform: orientationToTransform(wire.viaOrientation),
                        routeLayer: try layerNumbers.number(for: wire.layerName),
                        properties: regularRouteProperties(net: net, wire: provenance))))
                }
            }
        }

        for specialNet in doc.specialNets {
            for segment in specialNet.routing {
                let points = try validatedSpecialRoutePoints(segment, netName: specialNet.name)
                let coordinatePoints = segment.points.filter { $0.viaName == nil }
                for index in 1..<points.count {
                    let begin = coordinatePoints[index - 1].ext ?? 0
                    let end = coordinatePoints[index].ext ?? 0
                    var part = segment
                    part.points = [
                        DEFRoutePoint(x: points[index - 1].x, y: points[index - 1].y, ext: coordinatePoints[index - 1].ext),
                        DEFRoutePoint(x: points[index].x, y: points[index].y, ext: coordinatePoints[index].ext)]
                    if points.count == 2 { part.points = coordinatePoints }
                    elements.append(.path(IRPath(
                        layer: try layerNumbers.number(for: segment.layerName), datatype: 0,
                        pathType: begin == 0 && end == 0 ? .flush : .customExtension,
                        width: segment.width, points: [points[index - 1], points[index]],
                        properties: specialRouteProperties(net: specialNet, segment: part),
                        beginExtension: begin == 0 && end == 0 ? nil : begin,
                        endExtension: begin == 0 && end == 0 ? nil : end)))
                }
                if let via = segment.points.last, let name = via.viaName, let origin = points.last {
                    var provenance = segment
                    provenance.points = []
                    elements.append(.via(IRVia(viaName: name, origin: origin,
                        transform: orientationToTransform(via.viaOrientation ?? .n),
                        routeLayer: try layerNumbers.number(for: segment.layerName),
                        properties: specialRouteProperties(net: specialNet, segment: provenance))))
                }
            }
        }

        // Pin labels
        for pin in doc.pins {
            elements.append(.text(IRText(
                layer: 0, texttype: 0,
                transform: .identity,
                position: IRPoint(x: pin.x, y: pin.y),
                string: pin.name,
                properties: pinProperties(pin)
            )))
        }

        if topProperties.isEmpty {
            topProperties = []
        }
        let topCell = IRCell(
            name: doc.designName.isEmpty ? "TOP" : doc.designName,
            elements: elements,
            properties: topProperties
        )
        let macroCells = doc.components
            .map(\.macro)
            .filter { !$0.isEmpty && $0 != topCell.name }
            .reduce(into: [String]()) { names, macroName in
                if !names.contains(macroName) {
                    names.append(macroName)
                }
            }
            .map { IRCell(name: $0) }
        let databaseUnitScale = try DatabaseUnitScale(
            databaseUnitsPerMicrometer: doc.dbuPerMicron
        )
        return IRLibrary(
            name: doc.designName,
            databaseUnitScale: databaseUnitScale,
            cells: [topCell] + macroCells
        )
    }

    /// Convert an IRLibrary to a DEFDocument.
    public static func toDEFDocument(_ library: IRLibrary) throws -> DEFDocument {
        var doc = DEFDocument(
            designName: library.name,
            dbuPerMicron: library.databaseUnitScale.databaseUnitsPerMicrometer
        )
        // FIXME(INCOMPLETE_IMPLEMENTATION): Hierarchical via export requires resolved flattening.
        // Production DEF inverse conversion must fail until every child placement can retain
        // its transformed master and net provenance in top-level route records.
        for cell in library.cells.dropFirst() {
            for element in cell.elements {
                if case .via(let via) = element {
                    throw DEFIRConverterError.unsupportedRouteGeometry(netName: "", layerName: String(via.routeLayer),
                        reason: "DEF cannot preserve a via placement in a non-top cell without resolved flattening.")
                }
            }
        }
        guard let topCell = library.cells.first else { return doc }
        let hasPinMetadata = propertyValue(topCell.properties, key: pinCountPropertyKey) != nil

        doc.nets = netRecords(from: topCell.properties)
        doc.specialNets = specialNetRecords(from: topCell.properties)
        doc.pins = pinRecords(from: topCell.properties)
        doc.viaDefs = viaDefRecords(from: topCell.properties)

        for element in topCell.elements {
            switch element {
            case .via(let via):
                try appendVia(via, to: &doc)
            case .cellRef(let ref):
                let orient = try transformToOrientation(ref.transform)
                doc.components.append(DEFComponent(
                    name: propertyValue(ref.properties, key: componentNamePropertyKey) ?? ref.cellName,
                    macro: ref.cellName,
                    x: ref.origin.x,
                    y: ref.origin.y,
                    orientation: orient,
                    placementStatus: placementStatus(from: ref.properties) ?? .placed
                ))
            case .boundary(let boundary):
                if doc.dieArea == nil, boundary.layer == 0 {
                    doc.dieArea = dieArea(from: boundary)
                }
            case .text(let text):
                guard !hasPinMetadata else { break }
                doc.pins.append(DEFPin(
                    name: propertyValue(text.properties, key: pinNamePropertyKey) ?? text.string,
                    netName: propertyValue(text.properties, key: pinNetNamePropertyKey),
                    x: text.position.x,
                    y: text.position.y,
                    orientation: try transformToOrientation(text.transform),
                    placementStatus: pinPlacementStatus(from: text.properties) ?? .placed
                ))
            case .path(let path):
                try appendRoute(path, to: &doc)
            default:
                break
            }
        }

        return doc
    }

    private static func documentProperties(_ doc: DEFDocument) -> [IRProperty] {
        var properties: [IRProperty] = []

        if !doc.nets.isEmpty {
            properties.append(property(key: netCountPropertyKey, value: String(doc.nets.count)))
            for (index, net) in doc.nets.enumerated() {
                let prefix = "\(netPropertyPrefix).\(index)"
                properties.append(property(key: "\(prefix).name", value: net.name))
                if let use = net.use {
                    properties.append(property(key: "\(prefix).use", value: use.rawValue))
                }
                if !net.connections.isEmpty {
                    properties.append(property(
                        key: "\(prefix).connections",
                        value: encodeConnections(net.connections)
                    ))
                }
            }
        }

        if !doc.specialNets.isEmpty {
            properties.append(property(key: specialNetCountPropertyKey, value: String(doc.specialNets.count)))
            for (index, net) in doc.specialNets.enumerated() {
                let prefix = "\(specialNetPropertyPrefix).\(index)"
                properties.append(property(key: "\(prefix).name", value: net.name))
                if let use = net.use {
                    properties.append(property(key: "\(prefix).use", value: use.rawValue))
                }
                if let source = net.source {
                    properties.append(property(key: "\(prefix).source", value: source))
                }
                if let weight = net.weight {
                    properties.append(property(key: "\(prefix).weight", value: String(weight)))
                }
                if !net.connections.isEmpty {
                    properties.append(property(
                        key: "\(prefix).connections",
                        value: encodeConnections(net.connections)
                    ))
                }
            }
        }

        if !doc.pins.isEmpty {
            properties.append(property(key: pinCountPropertyKey, value: String(doc.pins.count)))
            for (index, pin) in doc.pins.enumerated() {
                let prefix = "\(pinPropertyPrefix).\(index)"
                properties.append(property(key: "\(prefix).name", value: pin.name))
                if let netName = pin.netName {
                    properties.append(property(key: "\(prefix).netName", value: netName))
                }
                properties.append(property(key: "\(prefix).x", value: String(pin.x)))
                properties.append(property(key: "\(prefix).y", value: String(pin.y)))
                properties.append(property(key: "\(prefix).orientation", value: pin.orientation.rawValue))
                if let placementStatus = pin.placementStatus {
                    properties.append(property(key: "\(prefix).placementStatus", value: placementStatus.rawValue))
                }
            }
        }

        let encodedViaDefs = encodedViaDefRecords(doc.viaDefs)
        if !encodedViaDefs.isEmpty {
            properties.append(property(key: viaDefCountPropertyKey, value: String(encodedViaDefs.count)))
            for (index, encodedViaDef) in encodedViaDefs.enumerated() {
                properties.append(property(key: "\(viaDefPropertyPrefix).\(index).json", value: encodedViaDef))
            }
        }

        return properties
    }

    private static func regularRouteProperties(net: DEFNet, wire: DEFRouteWire) -> [IRProperty] {
        let properties = [
            property(key: routeKindPropertyKey, value: "net"),
            property(key: routeNetNamePropertyKey, value: net.name),
            property(key: routeStatusPropertyKey, value: wire.status.rawValue),
            property(key: routeLayerNamePropertyKey, value: wire.layerName),
        ]
        return properties
    }

    private static func specialRouteProperties(net: DEFSpecialNet, segment: DEFRouteSegment) -> [IRProperty] {
        var properties = [
            property(key: routeKindPropertyKey, value: "specialNet"),
            property(key: routeNetNamePropertyKey, value: net.name),
            property(key: routeStatusPropertyKey, value: segment.status.rawValue),
            property(key: routeLayerNamePropertyKey, value: segment.layerName),
            property(key: routeWidthPropertyKey, value: String(segment.width)),
            property(key: routeSpecialPointsPropertyKey, value: encodeSpecialPoints(segment.points)),
        ]
        if let shape = segment.shape {
            properties.append(property(key: routeShapePropertyKey, value: shape.rawValue))
        }
        return properties
    }

    private static func appendVia(_ via: IRVia, to doc: inout DEFDocument) throws {
        let netName = propertyValue(via.properties, key: routeNetNamePropertyKey) ?? ""
        let layerName = propertyValue(via.properties, key: routeLayerNamePropertyKey) ?? ""
        guard !via.viaName.isEmpty, via.routeLayer > 0, !netName.isEmpty, !layerName.isEmpty,
              let kind = propertyValue(via.properties, key: routeKindPropertyKey),
              let status = propertyValue(via.properties, key: routeStatusPropertyKey) else {
            throw DEFIRConverterError.invalidRouteGeometry(netName: netName, layerName: layerName,
                reason: "Via export requires a named master and exact DEF route provenance.")
        }
        let orientation = try transformToOrientation(via.transform)
        switch kind {
        case "net":
            guard let status = DEFRouteWire.RouteStatus(rawValue: status) else {
                throw DEFIRConverterError.invalidRouteGeometry(netName: netName, layerName: layerName, reason: "Invalid via route status.")
            }
            let index = ensureNet(named: netName, in: &doc)
            doc.nets[index].routing.append(DEFRouteWire(status: status, layerName: layerName,
                points: [via.origin], viaName: via.viaName, viaOrientation: orientation))
        case "specialNet":
            guard let status = DEFRouteSegment.RouteStatus(rawValue: status),
                  let rawWidth = propertyValue(via.properties, key: routeWidthPropertyKey),
                  let width = Int32(rawWidth), width > 0, width % 2 == 0 else {
                throw DEFIRConverterError.invalidRouteGeometry(netName: netName, layerName: layerName, reason: "Invalid special via route status or source width.")
            }
            let index = ensureSpecialNet(named: netName, in: &doc)
            doc.specialNets[index].routing.append(DEFRouteSegment(status: status, layerName: layerName, width: width,
                points: [DEFRoutePoint(x: via.origin.x, y: via.origin.y), DEFRoutePoint(viaName: via.viaName, viaOrientation: orientation)],
                shape: propertyValue(via.properties, key: routeShapePropertyKey).flatMap(DEFRouteSegment.RouteShape.init(rawValue:))))
        default:
            throw DEFIRConverterError.invalidRouteGeometry(netName: netName, layerName: layerName, reason: "Invalid via route kind.")
        }
    }

    private static func appendRoute(_ path: IRPath, to doc: inout DEFDocument) throws {
        guard propertyValue(path.properties, key: "def.route.viaName") == nil else {
            throw DEFIRConverterError.invalidRouteGeometry(netName: "", layerName: String(path.layer),
                reason: "Named vias require typed placements separate from path geometry.")
        }
        guard let kind = propertyValue(path.properties, key: routeKindPropertyKey),
              let netName = propertyValue(path.properties, key: routeNetNamePropertyKey) else {
            return
        }

        let layerName = propertyValue(path.properties, key: routeLayerNamePropertyKey) ?? String(path.layer)
        let statusValue = propertyValue(path.properties, key: routeStatusPropertyKey)
        switch kind {
        case "net":
            let status = statusValue.flatMap(DEFRouteWire.RouteStatus.init(rawValue:)) ?? .routed
            let wire = DEFRouteWire(
                status: status,
                layerName: layerName,
                points: path.points,
                pointExtensions: try exportedExtensions(path, regular: true, netName: netName, layerName: layerName)
            )
            let index = ensureNet(named: netName, in: &doc)
            doc.nets[index].routing.append(wire)
        case "specialNet":
            let status = statusValue.flatMap(DEFRouteSegment.RouteStatus.init(rawValue:)) ?? .routed
            let width = path.width
            let shape = propertyValue(path.properties, key: routeShapePropertyKey)
                .flatMap(DEFRouteSegment.RouteShape.init(rawValue:))
            let encodedPoints = propertyValue(path.properties, key: routeSpecialPointsPropertyKey).map(decodeSpecialPoints)
            guard encodedPoints?.allSatisfy({ $0.viaName == nil }) ?? true else {
                throw DEFIRConverterError.invalidRouteGeometry(netName: netName, layerName: layerName,
                    reason: "Named vias require typed placements separate from path geometry.")
            }
            var points = encodedPoints ?? path.points.map { DEFRoutePoint(x: $0.x, y: $0.y) }
            if resolvedPoints(for: DEFRouteSegment(layerName: layerName, points: points)) != path.points {
                points = path.points.map { DEFRoutePoint(x: $0.x, y: $0.y) }
            }
            let extensions = try exportedExtensions(path, regular: false, netName: netName, layerName: layerName)
            var coordinateIndex = 0
            for index in points.indices where points[index].viaName == nil {
                let extensionValue = extensions[coordinateIndex]
                if points[index].ext != nil || extensionValue != 0 { points[index].ext = extensionValue }
                coordinateIndex += 1
            }
            let segment = DEFRouteSegment(
                status: status,
                layerName: layerName,
                width: width,
                points: points,
                shape: shape
            )
            let index = ensureSpecialNet(named: netName, in: &doc)
            doc.specialNets[index].routing.append(segment)
        default:
            return
        }
    }

    private static func exportedExtensions(
        _ path: IRPath, regular: Bool, netName: String, layerName: String
    ) throws -> [Int32?] {
        guard path.points.count == 2 else {
            throw DEFIRConverterError.unsupportedRouteGeometry(netName: netName, layerName: layerName,
                reason: "DEF route export requires straight segment paths.")
        }
        switch path.pathType {
        case .halfWidthExtend where regular:
            return [nil, nil]
        case .flush:
            return [0, 0]
        case .customExtension:
            guard let begin = path.beginExtension, let end = path.endExtension, begin >= 0, end >= 0 else {
                throw DEFIRConverterError.invalidRouteGeometry(netName: netName, layerName: layerName,
                    reason: "DEF requires explicit nonnegative endpoint extensions.")
            }
            return [begin, end]
        case .halfWidthExtend where path.width > 0 && path.width % 2 == 0:
            return [path.width / 2, path.width / 2]
        default:
            throw DEFIRConverterError.unsupportedRouteGeometry(netName: netName, layerName: layerName,
                reason: "DEF cannot preserve this path end-cap profile.")
        }
    }

    private static func ensureNet(named name: String, in doc: inout DEFDocument) -> Int {
        if let index = doc.nets.firstIndex(where: { $0.name == name }) {
            return index
        }
        doc.nets.append(DEFNet(name: name))
        return doc.nets.count - 1
    }

    private static func ensureSpecialNet(named name: String, in doc: inout DEFDocument) -> Int {
        if let index = doc.specialNets.firstIndex(where: { $0.name == name }) {
            return index
        }
        doc.specialNets.append(DEFSpecialNet(name: name))
        return doc.specialNets.count - 1
    }

    private static func netRecords(from properties: [IRProperty]) -> [DEFNet] {
        let count = propertyValue(properties, key: netCountPropertyKey).flatMap(Int.init) ?? 0
        return (0..<count).compactMap { index in
            let prefix = "\(netPropertyPrefix).\(index)"
            guard let name = propertyValue(properties, key: "\(prefix).name") else {
                return nil
            }
            let use = propertyValue(properties, key: "\(prefix).use")
                .flatMap(DEFSpecialNet.NetUse.init(rawValue:))
            let connections = propertyValue(properties, key: "\(prefix).connections")
                .map(decodeConnections) ?? []
            return DEFNet(name: name, connections: connections, use: use)
        }
    }

    private static func specialNetRecords(from properties: [IRProperty]) -> [DEFSpecialNet] {
        let count = propertyValue(properties, key: specialNetCountPropertyKey).flatMap(Int.init) ?? 0
        return (0..<count).compactMap { index in
            let prefix = "\(specialNetPropertyPrefix).\(index)"
            guard let name = propertyValue(properties, key: "\(prefix).name") else {
                return nil
            }
            let use = propertyValue(properties, key: "\(prefix).use")
                .flatMap(DEFSpecialNet.NetUse.init(rawValue:))
            let source = propertyValue(properties, key: "\(prefix).source")
            let weight = propertyValue(properties, key: "\(prefix).weight").flatMap(Int.init)
            let connections = propertyValue(properties, key: "\(prefix).connections")
                .map(decodeConnections) ?? []
            return DEFSpecialNet(
                name: name,
                connections: connections,
                use: use,
                source: source,
                weight: weight
            )
        }
    }

    private static func pinRecords(from properties: [IRProperty]) -> [DEFPin] {
        let count = propertyValue(properties, key: pinCountPropertyKey).flatMap(Int.init) ?? 0
        return (0..<count).compactMap { index in
            let prefix = "\(pinPropertyPrefix).\(index)"
            guard let name = propertyValue(properties, key: "\(prefix).name") else {
                return nil
            }
            let x = propertyValue(properties, key: "\(prefix).x").flatMap(Int32.init) ?? 0
            let y = propertyValue(properties, key: "\(prefix).y").flatMap(Int32.init) ?? 0
            let orientation = propertyValue(properties, key: "\(prefix).orientation")
                .flatMap(DEFOrientation.init(rawValue:)) ?? .n
            let placementStatus = propertyValue(properties, key: "\(prefix).placementStatus")
                .flatMap(DEFComponent.PlacementStatus.init(rawValue:))
            return DEFPin(
                name: name,
                netName: propertyValue(properties, key: "\(prefix).netName"),
                x: x,
                y: y,
                orientation: orientation,
                placementStatus: placementStatus
            )
        }
    }

    private static func viaDefRecords(from properties: [IRProperty]) -> [DEFViaDef] {
        let count = propertyValue(properties, key: viaDefCountPropertyKey).flatMap(Int.init) ?? 0
        var viaDefs: [DEFViaDef] = []
        for index in 0..<count {
            let key = "\(viaDefPropertyPrefix).\(index).json"
            guard let rawValue = propertyValue(properties, key: key),
                  let viaDef = decodeViaDef(rawValue) else {
                continue
            }
            viaDefs.append(viaDef)
        }
        return viaDefs
    }

    private static func encodedViaDefRecords(_ viaDefs: [DEFViaDef]) -> [String] {
        var encodedViaDefs: [String] = []
        for viaDef in viaDefs {
            if let encoded = encodeViaDef(viaDef) {
                encodedViaDefs.append(encoded)
            }
        }
        return encodedViaDefs
    }

    private static func encodeViaDef(_ viaDef: DEFViaDef) -> String? {
        do {
            return try JSONEncoder().encode(viaDef).base64EncodedString()
        } catch {
            return nil
        }
    }

    private static func decodeViaDef(_ rawValue: String) -> DEFViaDef? {
        guard let data = Data(base64Encoded: rawValue) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(DEFViaDef.self, from: data)
        } catch {
            return nil
        }
    }

    private static func componentProperties(_ component: DEFComponent) -> [IRProperty] {
        var properties = [
            property(key: componentNamePropertyKey, value: component.name),
        ]
        if let placementStatus = component.placementStatus {
            properties.append(property(key: placementStatusPropertyKey, value: placementStatus.rawValue))
        }
        return properties
    }

    private static func pinProperties(_ pin: DEFPin) -> [IRProperty] {
        var properties = [
            property(key: pinNamePropertyKey, value: pin.name),
        ]
        if let netName = pin.netName {
            properties.append(property(key: pinNetNamePropertyKey, value: netName))
        }
        if let placementStatus = pin.placementStatus {
            properties.append(property(key: pinPlacementStatusPropertyKey, value: placementStatus.rawValue))
        }
        return properties
    }

    private static func property(key: String, value: String) -> IRProperty {
        IRProperty(attribute: 0, value: "\(key)=\(value)")
    }

    private static func propertyValue(_ properties: [IRProperty], key: String) -> String? {
        for property in properties {
            let parts = property.value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == key else {
                continue
            }
            return String(parts[1])
        }
        return nil
    }

    private static func placementStatus(from properties: [IRProperty]) -> DEFComponent.PlacementStatus? {
        guard let rawValue = propertyValue(properties, key: placementStatusPropertyKey) else {
            return nil
        }
        return DEFComponent.PlacementStatus(rawValue: rawValue)
    }

    private static func pinPlacementStatus(from properties: [IRProperty]) -> DEFComponent.PlacementStatus? {
        guard let rawValue = propertyValue(properties, key: pinPlacementStatusPropertyKey) else {
            return nil
        }
        return DEFComponent.PlacementStatus(rawValue: rawValue)
    }

    private static func dieArea(from boundary: IRBoundary) -> DEFDieArea? {
        var points = boundary.points
        if points.count > 1, points.first == points.last {
            points.removeLast()
        }
        guard points.count >= 2 else {
            return nil
        }
        return DEFDieArea(points: points)
    }

    private static func resolvedPoints(for segment: DEFRouteSegment) -> [IRPoint] {
        var points: [IRPoint] = []
        var previousX: Int32 = 0
        var previousY: Int32 = 0
        for point in segment.points {
            guard point.viaName == nil else { continue }
            let resolved = point.resolved(previousX: previousX, previousY: previousY)
            previousX = resolved.x
            previousY = resolved.y
            points.append(resolved)
        }
        return points
    }

    private static func validatedRegularRoutePoints(
        _ wire: DEFRouteWire,
        netName: String
    ) throws -> [IRPoint] {
        guard !wire.layerName.isEmpty else {
            throw DEFIRConverterError.invalidRouteGeometry(
                netName: netName,
                layerName: wire.layerName,
                reason: "DEF regular route requires an explicit layer name."
            )
        }
        guard wire.points.count >= 2 || (wire.points.count == 1 && wire.viaName?.isEmpty == false) else {
            throw DEFIRConverterError.invalidRouteGeometry(
                netName: netName,
                layerName: wire.layerName,
                reason: "DEF regular route requires at least two placement points."
            )
        }
        guard wire.viaName == nil || wire.viaName?.isEmpty == false else {
            throw DEFIRConverterError.invalidRouteGeometry(netName: netName, layerName: wire.layerName,
                reason: "Via master names must be nonempty.")
        }
        guard !wire.taper && wire.style == nil else {
            throw DEFIRConverterError.unsupportedRouteGeometry(netName: netName, layerName: wire.layerName,
                reason: "TAPER and STYLE profiles require additional geometry semantics.")
        }
        guard wire.pointExtensions.isEmpty || wire.pointExtensions.count == wire.points.count,
              wire.pointExtensions.allSatisfy({ $0.map { $0 >= 0 } ?? true }) else {
            throw DEFIRConverterError.invalidRouteGeometry(netName: netName, layerName: wire.layerName,
                reason: "Regular route extensions must align with points and be nonnegative.")
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Standalone point extensions lack wire geometry.
        // DEF import must reject them until a standard placement interpretation is implemented.
        guard wire.points.count != 1 || wire.pointExtensions.allSatisfy({ $0 == nil }) else {
            throw DEFIRConverterError.unsupportedRouteGeometry(netName: netName, layerName: wire.layerName,
                reason: "Standalone via placements cannot carry wire extensions.")
        }
        try validateOrthogonalSegments(wire.points, netName: netName, layerName: wire.layerName)
        return wire.points
    }

    private static func validatedSpecialRoutePoints(
        _ segment: DEFRouteSegment,
        netName: String
    ) throws -> [IRPoint] {
        guard !segment.layerName.isEmpty else {
            throw DEFIRConverterError.invalidRouteGeometry(
                netName: netName,
                layerName: segment.layerName,
                reason: "DEF special route requires an explicit layer name."
            )
        }
        guard segment.width > 0 else {
            throw DEFIRConverterError.invalidRouteGeometry(
                netName: netName,
                layerName: segment.layerName,
                reason: "DEF special route requires a positive width."
            )
        }
        guard segment.width % 2 == 0 else {
            throw DEFIRConverterError.invalidRouteGeometry(netName: netName, layerName: segment.layerName,
                reason: "SPECIALNETS requires an even DBU width.")
        }
        let points = resolvedPoints(for: segment)
        guard points.count >= 2 || (points.count == 1 && segment.points.last?.viaName?.isEmpty == false) else {
            throw DEFIRConverterError.invalidRouteGeometry(
                netName: netName,
                layerName: segment.layerName,
                reason: "DEF special route requires at least two placement points."
            )
        }
        guard let first = segment.points.first, first.x != nil, first.y != nil, first.viaName == nil,
              segment.points.dropLast().allSatisfy({ $0.viaName == nil }),
              segment.points.allSatisfy({ ($0.ext.map { $0 >= 0 } ?? true) && ($0.viaName == nil || $0.viaName?.isEmpty == false) }) else {
            throw DEFIRConverterError.invalidRouteGeometry(netName: netName, layerName: segment.layerName,
                reason: "Special routes require an explicit first point, nonnegative extensions, and only a terminal via.")
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Standalone point extensions lack wire geometry.
        // DEF import must reject them until a standard placement interpretation is implemented.
        guard points.count != 1 || segment.points.allSatisfy({ $0.ext == nil }) else {
            throw DEFIRConverterError.unsupportedRouteGeometry(netName: netName, layerName: segment.layerName,
                reason: "Standalone via placements cannot carry wire extensions.")
        }
        try validateOrthogonalSegments(points, netName: netName, layerName: segment.layerName)
        return points
    }

    private static func validateOrthogonalSegments(_ points: [IRPoint], netName: String, layerName: String) throws {
        for index in 1..<points.count {
            let a = points[index - 1], b = points[index]
            guard a != b else {
                throw DEFIRConverterError.invalidRouteGeometry(netName: netName, layerName: layerName,
                    reason: "Zero-length DEF wire segments are invalid.")
            }
            guard a.x == b.x || a.y == b.y else {
                throw DEFIRConverterError.unsupportedRouteGeometry(netName: netName, layerName: layerName,
                    reason: "Non-orthogonal DEF routes require octagonal or explicit STYLE geometry.")
            }
        }
    }

    private static func validateLayerNumberMapping(
        _ layerNumbers: DEFLayerNumberMapping,
        for document: DEFDocument
    ) throws {
        var layerNameByNumber: [Int16: String] = [:]
        for layerName in routeLayerNames(in: document) {
            let number = try layerNumbers.number(for: layerName)
            if let existingLayerName = layerNameByNumber[number],
               existingLayerName.caseInsensitiveCompare(layerName) != .orderedSame {
                throw DEFIRConverterError.duplicateMappedLayerNumber(
                    layerName: layerName,
                    existingLayerName: existingLayerName,
                    layerNumber: number
                )
            }
            layerNameByNumber[number] = layerName
        }
    }

    private static func routeLayerNames(in document: DEFDocument) -> [String] {
        var layerNames: [String] = []
        for net in document.nets {
            for wire in net.routing where !wire.layerName.isEmpty {
                appendUnique(wire.layerName, to: &layerNames)
            }
        }
        for specialNet in document.specialNets {
            for segment in specialNet.routing where !segment.layerName.isEmpty {
                appendUnique(segment.layerName, to: &layerNames)
            }
        }
        return layerNames
    }

    private static func appendUnique(_ layerName: String, to layerNames: inout [String]) {
        guard !layerNames.contains(where: { $0.caseInsensitiveCompare(layerName) == .orderedSame }) else {
            return
        }
        layerNames.append(layerName)
    }

    private static func encodeConnections(_ connections: [DEFConnection]) -> String {
        connections
            .map { "\(escape($0.componentName))/\(escape($0.pinName))" }
            .joined(separator: "|")
    }

    private static func decodeConnections(_ rawValue: String) -> [DEFConnection] {
        guard !rawValue.isEmpty else { return [] }
        return rawValue.split(separator: "|", omittingEmptySubsequences: false).compactMap { item in
            let parts = item.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return DEFConnection(componentName: unescape(String(parts[0])), pinName: unescape(String(parts[1])))
        }
    }

    private static func encodeSpecialPoints(_ points: [DEFRoutePoint]) -> String {
        points.map { point in
            let x = point.x.map(String.init) ?? "*"
            let y = point.y.map(String.init) ?? "*"
            let ext = point.ext.map(String.init) ?? "*"
            let viaName = point.viaName.map(escape) ?? "*"
            return "\(x),\(y),\(ext),\(viaName)"
        }
        .joined(separator: "|")
    }

    private static func decodeSpecialPoints(_ rawValue: String) -> [DEFRoutePoint] {
        guard !rawValue.isEmpty else { return [] }
        return rawValue.split(separator: "|", omittingEmptySubsequences: false).map { item in
            let parts = item.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            let x = parts.count > 0 && parts[0] != "*" ? Int32(parts[0]) : nil
            let y = parts.count > 1 && parts[1] != "*" ? Int32(parts[1]) : nil
            let ext = parts.count > 2 && parts[2] != "*" ? Int32(parts[2]) : nil
            let viaName = parts.count > 3 && parts[3] != "*" ? unescape(parts[3]) : nil
            return DEFRoutePoint(x: x, y: y, ext: ext, viaName: viaName)
        }
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "|", with: "%7C")
            .replacingOccurrences(of: "/", with: "%2F")
            .replacingOccurrences(of: ",", with: "%2C")
    }

    private static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "%2C", with: ",")
            .replacingOccurrences(of: "%2F", with: "/")
            .replacingOccurrences(of: "%7C", with: "|")
            .replacingOccurrences(of: "%25", with: "%")
    }

    // MARK: - Orientation Mapping

    public static func orientationToTransform(_ orient: DEFOrientation) -> IRTransform {
        switch orient {
        case .n:  return IRTransform(mirrorX: false, angle: 0)
        case .s:  return IRTransform(mirrorX: false, angle: 180)
        case .w:  return IRTransform(mirrorX: false, angle: 90)
        case .e:  return IRTransform(mirrorX: false, angle: 270)
        case .fn: return IRTransform(mirrorX: true, angle: 180)
        case .fs: return IRTransform(mirrorX: true, angle: 0)
        case .fw: return IRTransform(mirrorX: true, angle: 90)
        case .fe: return IRTransform(mirrorX: true, angle: 270)
        }
    }

    public static func transformToOrientation(_ transform: IRTransform) throws -> DEFOrientation {
        guard transform.angle.isFinite, transform.magnification == 1 else {
            throw DEFIRConverterError.unrepresentableTransform
        }
        let remainder = transform.angle.truncatingRemainder(dividingBy: 360)
        switch remainder {
        case 0: return transform.mirrorX ? .fs : .n
        case 90, -270: return transform.mirrorX ? .fw : .w
        case 180, -180: return transform.mirrorX ? .fn : .s
        case 270, -90: return transform.mirrorX ? .fe : .e
        default: throw DEFIRConverterError.unrepresentableTransform
        }
    }
}
