import Foundation
import CircuiteFoundation
import LayoutIR

/// Reads a CIF text file and converts it to an `IRLibrary`.
public enum CIFLibraryReader {
    public static func read(
        _ data: Data,
        databaseUnitScale: DatabaseUnitScale
    ) throws -> IRLibrary {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CIFError.invalidEncoding
        }

        let commands = try CIFTokenizer.tokenize(text)
        let reservedNumericLayerIDs = Set(commands.compactMap { commandText -> Int16? in
            let parts = commandText.split(whereSeparator: { $0.isWhitespace })
            guard parts.count == 2, parts[0] == "L" else { return nil }
            return Int16(parts[1])
        })
        var cells: [IRCell] = []
        var currentCellName: String?
        var currentCellID: Int?
        var currentCellHasExplicitName = false
        var cellNamesByID: [Int: String] = [:]
        var currentScale = 1.0
        var currentElements: [IRElement] = []
        var currentLayer: Int16 = 0
        var layerTable: [String: Int16] = [:]
        var usedLayerIDs: Set<Int16> = []
        var nextLayerID: Int16 = 1
        var ended = false

        for commandText in commands {
            if ended { throw CIFError.commandAfterEnd(commandText) }
            let parts = commandText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let command = parts.first else {
                throw CIFError.invalidCommand(command: commandText, reason: "empty command")
            }

            switch command {
            case "DS":
                guard currentCellName == nil else { throw CIFError.nestedCellDefinition }
                guard parts.count == 3 || parts.count == 4 else {
                    throw CIFError.invalidCommand(command: commandText, reason: "DS requires cell, numerator and optional denominator")
                }
                let cellID = try integer(parts[1])
                let numerator = try integer(parts[2])
                if parts.count == 4 {
                    let denominator = try integer(parts[3])
                    guard denominator != 0 else {
                        throw CIFError.invalidCommand(command: commandText, reason: "scale denominator is zero")
                    }
                    currentScale = Double(numerator) / Double(denominator)
                } else {
                    guard numerator != 0 else {
                        throw CIFError.invalidCommand(command: commandText, reason: "scale denominator is zero")
                    }
                    currentScale = 1.0 / Double(numerator)
                }
                guard currentScale.isFinite, currentScale > 0 else {
                    throw CIFError.invalidCommand(command: commandText, reason: "scale must be finite and positive")
                }
                currentCellName = "CELL_\(cellID)"
                currentCellID = cellID
                currentCellHasExplicitName = false
                currentElements = []
                currentLayer = 0

            case "DF":
                guard parts.count == 1 else {
                    throw CIFError.invalidCommand(command: commandText, reason: "DF accepts no operands")
                }
                guard let name = currentCellName else { throw CIFError.unmatchedCellEnd }
                guard let cellID = currentCellID else { throw CIFError.unmatchedCellEnd }
                guard cellNamesByID[cellID] == nil else {
                    throw CIFError.invalidCommand(command: commandText, reason: "cell identifier is duplicated")
                }
                cellNamesByID[cellID] = name
                cells.append(IRCell(name: name, elements: currentElements))
                currentCellName = nil
                currentCellID = nil
                currentCellHasExplicitName = false
                currentElements = []

            case "L":
                try requireCell(currentCellName, command: commandText)
                guard parts.count == 2, !parts[1].isEmpty else {
                    throw CIFError.invalidCommand(command: commandText, reason: "L requires one layer name")
                }
                let layerName = parts[1]
                if let existing = layerTable[layerName] {
                    currentLayer = existing
                } else if let numericLayer = Int16(layerName) {
                    currentLayer = numericLayer
                    layerTable[layerName] = numericLayer
                    usedLayerIDs.insert(numericLayer)
                } else {
                    while usedLayerIDs.contains(nextLayerID) || reservedNumericLayerIDs.contains(nextLayerID) {
                        guard nextLayerID < Int16.max else {
                            throw CIFError.invalidCommand(command: commandText, reason: "layer identifier space is exhausted")
                        }
                        nextLayerID += 1
                    }
                    currentLayer = nextLayerID
                    layerTable[layerName] = nextLayerID
                    usedLayerIDs.insert(nextLayerID)
                    if nextLayerID < Int16.max { nextLayerID += 1 }
                }

            case "B":
                try requireCell(currentCellName, command: commandText)
                guard parts.count == 5 || parts.count == 7 else {
                    throw CIFError.invalidCommand(command: commandText, reason: "B requires four coordinates and an optional direction vector")
                }
                let values = try integers(Array(parts.dropFirst()))
                let length = try scaled(values[0], by: currentScale)
                let width = try scaled(values[1], by: currentScale)
                guard length > 0, width > 0 else {
                    throw CIFError.invalidCommand(command: commandText, reason: "box dimensions must be positive")
                }
                let centerX = try scaled(values[2], by: currentScale)
                let centerY = try scaled(values[3], by: currentScale)
                let points = try boxPoints(
                    length: length,
                    width: width,
                    centerX: centerX,
                    centerY: centerY,
                    direction: values.count == 6 ? (values[4], values[5]) : nil,
                    command: commandText
                )
                currentElements.append(.boundary(IRBoundary(
                    layer: currentLayer,
                    datatype: 0,
                    points: points,
                    properties: []
                )))

            case "W":
                try requireCell(currentCellName, command: commandText)
                guard parts.count >= 6, (parts.count - 2).isMultiple(of: 2) else {
                    throw CIFError.invalidCommand(command: commandText, reason: "W requires a width and at least two coordinate pairs")
                }
                let values = try integers(Array(parts.dropFirst()))
                let width = try scaled(values[0], by: currentScale)
                guard width >= 0 else {
                    throw CIFError.invalidCommand(command: commandText, reason: "wire width cannot be negative")
                }
                let points = try pointPairs(Array(values.dropFirst()), scale: currentScale)
                currentElements.append(.path(IRPath(
                    layer: currentLayer,
                    datatype: 0,
                    pathType: .flush,
                    width: width,
                    points: points,
                    properties: []
                )))

            case "P":
                try requireCell(currentCellName, command: commandText)
                guard parts.count >= 7, (parts.count - 1).isMultiple(of: 2) else {
                    throw CIFError.invalidCommand(command: commandText, reason: "P requires at least three coordinate pairs")
                }
                var points = try pointPairs(try integers(Array(parts.dropFirst())), scale: currentScale)
                if points.first != points.last, let first = points.first { points.append(first) }
                currentElements.append(.boundary(IRBoundary(
                    layer: currentLayer,
                    datatype: 0,
                    points: points,
                    properties: []
                )))

            case "C":
                try requireCell(currentCellName, command: commandText)
                currentElements.append(.cellRef(try parseCellReference(parts, scale: currentScale, command: commandText)))

            case "9":
                try requireCell(currentCellName, command: commandText)
                if parts.count == 2, !parts[1].isEmpty {
                    guard !currentCellHasExplicitName else {
                        throw CIFError.invalidCommand(command: commandText, reason: "cell name is already defined")
                    }
                    guard !cells.contains(where: { $0.name == parts[1] }) else {
                        throw CIFError.duplicateCellName(parts[1])
                    }
                    currentCellName = parts[1]
                    currentCellHasExplicitName = true
                    continue
                }
                guard parts.count == 4, !parts[1].isEmpty else {
                    throw CIFError.invalidCommand(command: commandText, reason: "9 requires text and two coordinates")
                }
                currentElements.append(.text(IRText(
                    layer: currentLayer,
                    texttype: 0,
                    transform: .identity,
                    position: IRPoint(
                        x: try scaled(try integer(parts[2]), by: currentScale),
                        y: try scaled(try integer(parts[3]), by: currentScale)
                    ),
                    string: parts[1],
                    properties: []
                )))

            case "E":
                guard parts.count == 1 else {
                    throw CIFError.invalidCommand(command: commandText, reason: "E accepts no operands")
                }
                if let currentCellName { throw CIFError.unterminatedCell(currentCellName) }
                ended = true

            default:
                throw CIFError.unsupportedCommand(command)
            }
        }

        if let currentCellName { throw CIFError.unterminatedCell(currentCellName) }
        guard ended else { throw CIFError.missingEndCommand }
        let resolvedCells = try cells.map { cell in
            let elements = try cell.elements.map { element -> IRElement in
                guard case .cellRef(var reference) = element else {
                    return element
                }
                guard reference.cellName.hasPrefix("CELL_"),
                      let cellID = Int(reference.cellName.dropFirst("CELL_".count)),
                      let resolvedName = cellNamesByID[cellID] else {
                    throw CIFError.unresolvedCellReference(reference.cellName)
                }
                reference.cellName = resolvedName
                return .cellRef(reference)
            }
            return IRCell(name: cell.name, elements: elements)
        }
        return IRLibrary(name: "CIF", databaseUnitScale: databaseUnitScale, cells: resolvedCells)
    }

    private static func requireCell(_ cellName: String?, command: String) throws {
        guard cellName != nil else { throw CIFError.elementOutsideCell(command) }
    }

    private static func integer(_ token: String) throws -> Int {
        guard let value = Int(token) else { throw CIFError.invalidNumber(token) }
        return value
    }

    private static func integers(_ tokens: [String]) throws -> [Int] {
        try tokens.map(integer)
    }

    private static func scaled(_ value: Int, by scale: Double) throws -> Int32 {
        let scaledValue = Double(value) * scale
        guard scaledValue.isFinite,
              scaledValue >= Double(Int32.min),
              scaledValue <= Double(Int32.max) else {
            throw CIFError.invalidNumber(String(value))
        }
        return Int32(scaledValue.rounded(.towardZero))
    }

    private static func pointPairs(_ values: [Int], scale: Double) throws -> [IRPoint] {
        guard values.count.isMultiple(of: 2) else {
            throw CIFError.invalidCommand(command: values.map(String.init).joined(separator: " "), reason: "coordinate list has an odd number of values")
        }
        return try stride(from: 0, to: values.count, by: 2).map { index in
            IRPoint(x: try scaled(values[index], by: scale), y: try scaled(values[index + 1], by: scale))
        }
    }

    private static func boxPoints(
        length: Int32,
        width: Int32,
        centerX: Int32,
        centerY: Int32,
        direction: (Int, Int)?,
        command: String
    ) throws -> [IRPoint] {
        let halfLength = Double(length) / 2
        let halfWidth = Double(width) / 2
        let directionX = Double(direction?.0 ?? 1)
        let directionY = Double(direction?.1 ?? 0)
        let magnitude = (directionX * directionX + directionY * directionY).squareRoot()
        guard magnitude > 0 else {
            throw CIFError.invalidCommand(command: command, reason: "box direction vector cannot be zero")
        }
        let x = directionX / magnitude
        let y = directionY / magnitude
        let centerX = Double(centerX)
        let centerY = Double(centerY)
        let coordinates = [
            (centerX - halfLength * x + halfWidth * y, centerY - halfLength * y - halfWidth * x),
            (centerX + halfLength * x + halfWidth * y, centerY + halfLength * y - halfWidth * x),
            (centerX + halfLength * x - halfWidth * y, centerY + halfLength * y + halfWidth * x),
            (centerX - halfLength * x - halfWidth * y, centerY - halfLength * y + halfWidth * x),
        ]
        let points = try coordinates.map { coordinate -> IRPoint in
            guard coordinate.0 >= Double(Int32.min), coordinate.0 <= Double(Int32.max),
                  coordinate.1 >= Double(Int32.min), coordinate.1 <= Double(Int32.max) else {
                throw CIFError.invalidNumber(command)
            }
            return IRPoint(x: Int32(coordinate.0.rounded()), y: Int32(coordinate.1.rounded()))
        }
        return points + [points[0]]
    }

    private static func parseCellReference(
        _ parts: [String],
        scale: Double,
        command: String
    ) throws -> IRCellRef {
        guard parts.count >= 2 else {
            throw CIFError.invalidCommand(command: command, reason: "C requires a cell identifier")
        }
        let cellID = try integer(parts[1])
        var origin = IRPoint(x: 0, y: 0)
        var mirrorX = false
        var angle = 0.0
        var index = 2
        while index < parts.count {
            switch parts[index] {
            case "T":
                guard index + 2 < parts.count else {
                    throw CIFError.invalidCommand(command: command, reason: "T requires two coordinates")
                }
                origin = IRPoint(
                    x: try scaled(try integer(parts[index + 1]), by: scale),
                    y: try scaled(try integer(parts[index + 2]), by: scale)
                )
                index += 3
            case "M":
                guard index + 1 < parts.count else {
                    throw CIFError.invalidCommand(command: command, reason: "M requires X or Y")
                }
                switch parts[index + 1] {
                case "X":
                    mirrorX = true
                    angle += 180
                case "Y":
                    mirrorX = true
                default:
                    throw CIFError.invalidCommand(command: command, reason: "unsupported mirror axis")
                }
                index += 2
            case "R":
                guard index + 2 < parts.count else {
                    throw CIFError.invalidCommand(command: command, reason: "R requires a nonzero direction vector")
                }
                let x = try integer(parts[index + 1])
                let y = try integer(parts[index + 2])
                guard x != 0 || y != 0 else {
                    throw CIFError.invalidCommand(command: command, reason: "rotation direction vector cannot be zero")
                }
                angle += atan2(Double(y), Double(x)) * 180 / .pi
                index += 3
            default:
                throw CIFError.unsupportedCommand(parts[index])
            }
        }
        return IRCellRef(
            cellName: "CELL_\(cellID)",
            origin: origin,
            transform: IRTransform(mirrorX: mirrorX, magnification: 1, angle: angle),
            properties: []
        )
    }
}
