import Foundation
import CircuiteFoundation
import LayoutIR

/// Converts OASIS binary data to an IRLibrary.
public enum OASISLibraryReader {

    public static func read(_ data: Data) throws -> IRLibrary {
        var reader = OASISReader(data: data)

        // Magic
        try reader.validateMagic()

        // START record
        let startByte = try reader.readByte()
        guard startByte == OASISRecordType.start.rawValue else {
            throw OASISError.unexpectedRecord(got: startByte, expected: "START", offset: reader.currentOffset - 1)
        }
        let version = try reader.readAString()
        _ = version // "1.0"
        let unitOffset = reader.currentOffset
        let unitReal = try reader.readReal()
        let scale: DatabaseUnitScale
        do {
            scale = try DatabaseUnitScale(databaseUnitsPerMicrometer: 1.0 / unitReal)
        } catch let error as DatabaseUnitScaleError {
            throw OASISError.invalidUnits(offset: unitOffset, reason: error.localizedDescription)
        }
        let offsetFlag = try reader.readUnsignedInteger()
        if offsetFlag != 0 {
            // Offset tables present: 6 tables x 2 values (type + offset) = 12 values
            for _ in 0..<12 {
                _ = try reader.readUnsignedInteger()
            }
        }

        // Read records until END
        var cellNames: [String] = []
        var textStrings: [String] = []
        var propNames: [String] = []
        var propStrings: [String] = []
        var cells: [IRCell] = []
        var libraryName = ""

        while reader.hasMore {
            let recordByte = try reader.readByte()
            guard let recordType = OASISRecordType(rawValue: recordByte) else {
                // Skip unknown records
                throw OASISError.unknownRecordType(offset: reader.currentOffset - 1, rawValue: recordByte)
            }

            switch recordType {
            case .pad:
                continue
            case .end:
                // END record: read padding string and validation
                _ = try reader.readAString() // padding
                if reader.hasMore {
                    _ = try reader.readUnsignedInteger() // validation-scheme
                }
                let name = libraryName.isEmpty ? (cellNames.first ?? "OASIS") : libraryName
                return IRLibrary(name: name, databaseUnitScale: scale, cells: cells)
            case .propstring:
                let name = try reader.readAString()
                propStrings.append(name)
                if libraryName.isEmpty {
                    libraryName = name
                }
            case .propstringRef:
                // Explicit reference number assignment
                let refNum = try reader.readUnsignedInteger()
                let name = try reader.readAString()
                let index = try checkedTableIndex(refNum, context: "prop-string reference")
                appendPlaceholders(to: &propStrings, through: index)
                propStrings[index] = name
                if libraryName.isEmpty { libraryName = name }
            case .cellname:
                let name = try reader.readAString()
                cellNames.append(name)
            case .cellnameRef:
                let refNum = try reader.readUnsignedInteger()
                let name = try reader.readAString()
                let index = try checkedTableIndex(refNum, context: "cell-name reference")
                appendPlaceholders(to: &cellNames, through: index)
                cellNames[index] = name
            case .textstring:
                textStrings.append(try reader.readAString())
            case .textstringRef:
                let refNum = try reader.readUnsignedInteger()
                let name = try reader.readAString()
                let index = try checkedTableIndex(refNum, context: "text-string reference")
                appendPlaceholders(to: &textStrings, through: index)
                textStrings[index] = name
            case .propname:
                propNames.append(try reader.readAString())
            case .propnameRef:
                let refNum = try reader.readUnsignedInteger()
                let name = try reader.readAString()
                let index = try checkedTableIndex(refNum, context: "prop-name reference")
                appendPlaceholders(to: &propNames, through: index)
                propNames[index] = name
            case .cell:
                let cellName = try reader.readAString()
                let cell = try readCellContents(&reader, name: cellName, cellNames: cellNames, textStrings: textStrings, propNames: propNames)
                cells.append(cell)
            case .cellRef:
                let refNum = try reader.readUnsignedInteger()
                let cellName = try tableValue(cellNames, refNum: refNum, fallbackPrefix: "CELL_", context: "cell reference")
                let cell = try readCellContents(&reader, name: cellName, cellNames: cellNames, textStrings: textStrings, propNames: propNames)
                cells.append(cell)
            case .cblock:
                try reader.handleCBlock()
            default:
                throw OASISError.unexpectedRecord(
                    got: recordByte,
                    expected: "supported library record",
                    offset: reader.currentOffset - 1
                )
            }
        }

        let name = libraryName.isEmpty ? "OASIS" : libraryName
        return IRLibrary(name: name, databaseUnitScale: scale, cells: cells)
    }

    // MARK: - Cell Contents

    private static func readCellContents(
        _ reader: inout OASISReader,
        name: String,
        cellNames: [String],
        textStrings: [String],
        propNames: [String]
    ) throws -> IRCell {
        var elements: [IRElement] = []
        var modal = OASISModalState()

        while reader.hasMore {
            let nextByte = try reader.peekByte()
            guard let nextType = OASISRecordType(rawValue: nextByte) else {
                throw OASISError.unknownRecordType(offset: reader.currentOffset, rawValue: nextByte)
            }

            switch nextType {
            case .cell, .cellRef, .cellname, .cellnameRef, .end:
                return IRCell(name: name, elements: elements)
            case .xyAbsolute:
                _ = try reader.readByte()
            case .xyRelative:
                _ = try reader.readByte()
            case .rectangle:
                _ = try reader.readByte()
                try appendElements(
                    try readRectangle(&reader, modal: &modal),
                    reader: &reader,
                    modal: &modal,
                    elements: &elements,
                    propNames: propNames
                )
            case .polygon:
                _ = try reader.readByte()
                try appendElements(
                    try readPolygon(&reader, modal: &modal),
                    reader: &reader,
                    modal: &modal,
                    elements: &elements,
                    propNames: propNames
                )
            case .path:
                _ = try reader.readByte()
                try appendElements(
                    try readPath(&reader, modal: &modal),
                    reader: &reader,
                    modal: &modal,
                    elements: &elements,
                    propNames: propNames
                )
            case .text:
                _ = try reader.readByte()
                try appendElements(
                    try readText(&reader, modal: &modal, textStrings: textStrings),
                    reader: &reader,
                    modal: &modal,
                    elements: &elements,
                    propNames: propNames
                )
            case .placement:
                _ = try reader.readByte()
                let placed = try readPlacement(&reader, modal: &modal, withTransform: false, cellNames: cellNames)
                try appendElements(placed, reader: &reader, modal: &modal, elements: &elements, propNames: propNames)
            case .placementT:
                _ = try reader.readByte()
                let placed = try readPlacement(&reader, modal: &modal, withTransform: true, cellNames: cellNames)
                try appendElements(placed, reader: &reader, modal: &modal, elements: &elements, propNames: propNames)
            case .trapezoid:
                _ = try reader.readByte()
                try appendElements(
                    try readTrapezoid(&reader, modal: &modal, variant: .both),
                    reader: &reader,
                    modal: &modal,
                    elements: &elements,
                    propNames: propNames
                )
            case .trapezoidA:
                _ = try reader.readByte()
                try appendElements(
                    try readTrapezoid(&reader, modal: &modal, variant: .a),
                    reader: &reader,
                    modal: &modal,
                    elements: &elements,
                    propNames: propNames
                )
            case .trapezoidB:
                _ = try reader.readByte()
                try appendElements(
                    try readTrapezoid(&reader, modal: &modal, variant: .b),
                    reader: &reader,
                    modal: &modal,
                    elements: &elements,
                    propNames: propNames
                )
            case .ctrapezoid:
                _ = try reader.readByte()
                try appendElements(
                    try readCTrapezoid(&reader, modal: &modal),
                    reader: &reader,
                    modal: &modal,
                    elements: &elements,
                    propNames: propNames
                )
            case .circle:
                _ = try reader.readByte()
                try appendElements(
                    try readCircle(&reader, modal: &modal),
                    reader: &reader,
                    modal: &modal,
                    elements: &elements,
                    propNames: propNames
                )
            case .property:
                _ = try reader.readByte()
                let property = try readProperty(&reader, modal: &modal, propNames: propNames)
                if !elements.isEmpty {
                    attachProperty(&elements[elements.count - 1], property)
                }
            case .propertyRepeat:
                _ = try reader.readByte()
                applyPropertyRepeat(modal: &modal, elements: &elements)
            case .cblock:
                _ = try reader.readByte()
                try reader.handleCBlock()
            case .pad:
                _ = try reader.readByte()
            default:
                throw OASISError.unexpectedRecord(
                    got: nextByte,
                    expected: "supported cell content",
                    offset: reader.currentOffset
                )
            }
        }

        return IRCell(name: name, elements: elements)
    }

    private static func appendElements(
        _ newElements: [IRElement],
        reader: inout OASISReader,
        modal: inout OASISModalState,
        elements: inout [IRElement],
        propNames: [String]
    ) throws {
        let start = elements.count
        elements.append(contentsOf: newElements)
        try readTrailingProperties(
            &reader,
            modal: &modal,
            elements: &elements,
            range: start..<elements.count,
            propNames: propNames
        )
    }

    // MARK: - RECTANGLE

    private static func readRectangle(_ reader: inout OASISReader, modal: inout OASISModalState) throws -> [IRElement] {
        let infoByte = try reader.readByte()
        if infoByte & 0x01 != 0 { modal.layer = try reader.readUnsignedInteger() }
        if infoByte & 0x02 != 0 { modal.datatype = try reader.readUnsignedInteger() }
        if infoByte & 0x40 != 0 { modal.geometryW = try reader.readUnsignedInteger() }
        if infoByte & 0x20 != 0 { modal.geometryH = try reader.readUnsignedInteger() }
        // S-bit (0x80): square -- H = W, H field not present in stream
        if infoByte & 0x80 != 0 {
            modal.geometryH = modal.geometryW
        }
        if infoByte & 0x10 != 0 { modal.x = try reader.readSignedInteger() }
        if infoByte & 0x08 != 0 { modal.y = try reader.readSignedInteger() }

        let repetition = try readGeometryRepetitionIfPresent(infoByte: infoByte, reader: &reader, modal: &modal)

        let layer = try checkedInt16(modal.layer ?? 0, context: "rectangle layer")
        let datatype = try checkedInt16(modal.datatype ?? 0, context: "rectangle datatype")
        let x = try checkedInt32(modal.x ?? 0, context: "rectangle x")
        let y = try checkedInt32(modal.y ?? 0, context: "rectangle y")
        let w = try checkedInt32(modal.geometryW ?? 0, context: "rectangle width")
        let h = try checkedInt32(modal.geometryH ?? 0, context: "rectangle height")

        let points = try rectanglePoints(x: x, y: y, width: w, height: h, context: "rectangle points")

        return try expand(.boundary(IRBoundary(layer: layer, datatype: datatype, points: points, properties: [])), repetition: repetition)
    }

    private static func readGeometryRepetitionIfPresent(
        infoByte: UInt8,
        reader: inout OASISReader,
        modal: inout OASISModalState
    ) throws -> OASISRepetition? {
        guard infoByte & 0x04 != 0 else { return nil }
        let repetition = try readRepetitionWithReuse(&reader, modal: &modal)
        modal.lastRepetition = repetition
        return repetition
    }

    private static func expand(_ element: IRElement, repetition: OASISRepetition?) throws -> [IRElement] {
        guard let repetition else { return [element] }
        return try repetitionOffsets(for: repetition).map { offset in
            try translate(element, by: offset)
        }
    }

    private static func repetitionOffsets(for repetition: OASISRepetition) throws -> [OASISDisplacement] {
        switch repetition {
        case .grid(let columns, let rows, let colSpacing, let rowSpacing):
            var offsets: [OASISDisplacement] = []
            offsets.reserveCapacity(try checkedRepetitionElementCount(columns, rows, context: "grid repetition"))
            let colSpacing = try checkedInt64(colSpacing, context: "grid column spacing")
            let rowSpacing = try checkedInt64(rowSpacing, context: "grid row spacing")
            for row in 0..<rows {
                let rowIndex = try checkedInt64(row, context: "grid row index")
                for column in 0..<columns {
                    let columnIndex = try checkedInt64(column, context: "grid column index")
                    offsets.append(OASISDisplacement(
                        dx: try checkedMultiply(columnIndex, colSpacing, context: "grid x offset"),
                        dy: try checkedMultiply(rowIndex, rowSpacing, context: "grid y offset")
                    ))
                }
            }
            return offsets
        case .uniformRow(let count, let spacing):
            _ = try checkedRepetitionElementCount(count, context: "uniform row repetition")
            let spacing = try checkedInt64(spacing, context: "uniform row spacing")
            return try (0..<count).map {
                let index = try checkedInt64($0, context: "uniform row index")
                return OASISDisplacement(dx: try checkedMultiply(index, spacing, context: "uniform row offset"), dy: 0)
            }
        case .uniformColumn(let count, let spacing):
            _ = try checkedRepetitionElementCount(count, context: "uniform column repetition")
            let spacing = try checkedInt64(spacing, context: "uniform column spacing")
            return try (0..<count).map {
                let index = try checkedInt64($0, context: "uniform column index")
                return OASISDisplacement(dx: 0, dy: try checkedMultiply(index, spacing, context: "uniform column offset"))
            }
        case .variableRow(let spacings):
            return try cumulativeOffsets(spacings: spacings, axis: .x)
        case .variableColumn(let spacings):
            return try cumulativeOffsets(spacings: spacings, axis: .y)
        case .arbitraryGrid(let columns, let rows, let colDisplacement, let rowDisplacement):
            var offsets: [OASISDisplacement] = []
            offsets.reserveCapacity(try checkedRepetitionElementCount(columns, rows, context: "arbitrary grid repetition"))
            for row in 0..<rows {
                let rowIndex = try checkedInt64(row, context: "arbitrary grid row index")
                for column in 0..<columns {
                    let columnIndex = try checkedInt64(column, context: "arbitrary grid column index")
                    let columnDX = try checkedMultiply(columnIndex, colDisplacement.dx, context: "arbitrary grid column dx")
                    let rowDX = try checkedMultiply(rowIndex, rowDisplacement.dx, context: "arbitrary grid row dx")
                    let columnDY = try checkedMultiply(columnIndex, colDisplacement.dy, context: "arbitrary grid column dy")
                    let rowDY = try checkedMultiply(rowIndex, rowDisplacement.dy, context: "arbitrary grid row dy")
                    offsets.append(OASISDisplacement(
                        dx: try checkedAdd(columnDX, rowDX, context: "arbitrary grid x offset"),
                        dy: try checkedAdd(columnDY, rowDY, context: "arbitrary grid y offset")
                    ))
                }
            }
            return offsets
        case .variableDisplacementRow(let displacements),
             .variableDisplacementColumn(let displacements):
            return try cumulativeOffsets(displacements: displacements)
        }
    }

    private enum RepetitionAxis {
        case x
        case y
    }

    private static func cumulativeOffsets(spacings: [UInt64], axis: RepetitionAxis) throws -> [OASISDisplacement] {
        var offsets = [OASISDisplacement(dx: 0, dy: 0)]
        var current: Int64 = 0
        for spacing in spacings {
            current = try checkedAdd(current, checkedInt64(spacing, context: "variable repetition spacing"), context: "variable repetition offset")
            switch axis {
            case .x:
                offsets.append(OASISDisplacement(dx: current, dy: 0))
            case .y:
                offsets.append(OASISDisplacement(dx: 0, dy: current))
            }
        }
        return offsets
    }

    private static func cumulativeOffsets(displacements: [OASISDisplacement]) throws -> [OASISDisplacement] {
        var offsets = [OASISDisplacement(dx: 0, dy: 0)]
        var current = OASISDisplacement(dx: 0, dy: 0)
        for displacement in displacements {
            current = OASISDisplacement(
                dx: try checkedAdd(current.dx, displacement.dx, context: "variable displacement x offset"),
                dy: try checkedAdd(current.dy, displacement.dy, context: "variable displacement y offset")
            )
            offsets.append(current)
        }
        return offsets
    }

    private static func translate(_ element: IRElement, by offset: OASISDisplacement) throws -> IRElement {
        guard offset.dx != 0 || offset.dy != 0 else { return element }
        switch element {
        case .boundary(var boundary):
            boundary.points = try boundary.points.map { try translate($0, by: offset) }
            return .boundary(boundary)
        case .path(var path):
            path.points = try path.points.map { try translate($0, by: offset) }
            return .path(path)
        case .text(var text):
            text.position = try translate(text.position, by: offset)
            return .text(text)
        case .cellRef(var ref):
            ref.origin = try translate(ref.origin, by: offset)
            return .cellRef(ref)
        case .arrayRef:
            return element
        }
    }

    private static func translate(_ point: IRPoint, by offset: OASISDisplacement) throws -> IRPoint {
        try checkedPoint(
            x: checkedAdd(Int64(point.x), offset.dx, context: "translated point x"),
            y: checkedAdd(Int64(point.y), offset.dy, context: "translated point y"),
            context: "translated point"
        )
    }

    // MARK: - POLYGON

    private static func readPolygon(_ reader: inout OASISReader, modal: inout OASISModalState) throws -> [IRElement] {
        let infoByte = try reader.readByte()
        if infoByte & 0x01 != 0 { modal.layer = try reader.readUnsignedInteger() }
        if infoByte & 0x02 != 0 { modal.datatype = try reader.readUnsignedInteger() }

        var deltas: [IRPoint] = []
        if infoByte & 0x20 != 0 {
            deltas = try reader.readPointList()
        }

        if infoByte & 0x10 != 0 { modal.x = try reader.readSignedInteger() }
        if infoByte & 0x08 != 0 { modal.y = try reader.readSignedInteger() }

        let repetition = try readGeometryRepetitionIfPresent(infoByte: infoByte, reader: &reader, modal: &modal)

        let layer = try checkedInt16(modal.layer ?? 0, context: "polygon layer")
        let datatype = try checkedInt16(modal.datatype ?? 0, context: "polygon datatype")
        let originX = try checkedInt32(modal.x ?? 0, context: "polygon x")
        let originY = try checkedInt32(modal.y ?? 0, context: "polygon y")

        var points: [IRPoint] = [IRPoint(x: originX, y: originY)]
        var cx = Int64(originX)
        var cy = Int64(originY)
        for delta in deltas {
            cx = try checkedAdd(cx, Int64(delta.x), context: "polygon x")
            cy = try checkedAdd(cy, Int64(delta.y), context: "polygon y")
            points.append(try checkedPoint(x: cx, y: cy, context: "polygon point"))
        }
        points.append(IRPoint(x: originX, y: originY))

        return try expand(.boundary(IRBoundary(layer: layer, datatype: datatype, points: points, properties: [])), repetition: repetition)
    }

    // MARK: - PATH

    private static func readPath(_ reader: inout OASISReader, modal: inout OASISModalState) throws -> [IRElement] {
        let infoByte = try reader.readByte()
        if infoByte & 0x01 != 0 { modal.layer = try reader.readUnsignedInteger() }
        if infoByte & 0x02 != 0 { modal.datatype = try reader.readUnsignedInteger() }
        if infoByte & 0x40 != 0 { modal.pathHalfwidth = try reader.readUnsignedInteger() }

        var pathType: IRPathType = .flush
        if infoByte & 0x80 != 0 {
            let extScheme = try reader.readUnsignedInteger()
            pathType = irPathType(from: extScheme)
        }

        var deltas: [IRPoint] = []
        if infoByte & 0x20 != 0 {
            deltas = try reader.readPointList()
        }

        if infoByte & 0x10 != 0 { modal.x = try reader.readSignedInteger() }
        if infoByte & 0x08 != 0 { modal.y = try reader.readSignedInteger() }

        let repetition = try readGeometryRepetitionIfPresent(infoByte: infoByte, reader: &reader, modal: &modal)

        let layer = try checkedInt16(modal.layer ?? 0, context: "path layer")
        let datatype = try checkedInt16(modal.datatype ?? 0, context: "path datatype")
        let halfwidth = try checkedInt32(modal.pathHalfwidth ?? 0, context: "path halfwidth")
        let width = try checkedInt32(checkedMultiply(Int64(halfwidth), 2, context: "path width"), context: "path width")
        let originX = try checkedInt32(modal.x ?? 0, context: "path x")
        let originY = try checkedInt32(modal.y ?? 0, context: "path y")

        var points: [IRPoint] = [IRPoint(x: originX, y: originY)]
        var cx = Int64(originX)
        var cy = Int64(originY)
        for delta in deltas {
            cx = try checkedAdd(cx, Int64(delta.x), context: "path x")
            cy = try checkedAdd(cy, Int64(delta.y), context: "path y")
            points.append(try checkedPoint(x: cx, y: cy, context: "path point"))
        }

        return try expand(.path(IRPath(layer: layer, datatype: datatype, pathType: pathType, width: width, points: points, properties: [])), repetition: repetition)
    }

    // MARK: - TEXT

    private static func readText(_ reader: inout OASISReader, modal: inout OASISModalState, textStrings: [String]) throws -> [IRElement] {
        let infoByte = try reader.readByte()

        var textString = modal.textString ?? ""
        if infoByte & 0x40 != 0 {
            // C bit: check if N bit indicates reference
            if infoByte & 0x20 != 0 {
                // N=1: text-string reference number
                let refNum = try reader.readUnsignedInteger()
                textString = try tableValue(textStrings, refNum: refNum, fallbackPrefix: "", context: "text-string reference")
            } else {
                // N=0: inline text string
                textString = try reader.readAString()
            }
            modal.textString = textString
        }

        if infoByte & 0x01 != 0 { modal.textlayer = try reader.readUnsignedInteger() }
        if infoByte & 0x02 != 0 { modal.texttype = try reader.readUnsignedInteger() }
        if infoByte & 0x10 != 0 { modal.x = try reader.readSignedInteger() }
        if infoByte & 0x08 != 0 { modal.y = try reader.readSignedInteger() }

        let repetition = try readGeometryRepetitionIfPresent(infoByte: infoByte, reader: &reader, modal: &modal)

        let layer = try checkedInt16(modal.textlayer ?? 0, context: "text layer")
        let texttype = try checkedInt16(modal.texttype ?? 0, context: "text type")
        let x = try checkedInt32(modal.x ?? 0, context: "text x")
        let y = try checkedInt32(modal.y ?? 0, context: "text y")

        return try expand(.text(IRText(
            layer: layer,
            texttype: texttype,
            transform: .identity,
            position: IRPoint(x: x, y: y),
            string: textString,
            properties: []
        )), repetition: repetition)
    }

    // MARK: - PLACEMENT

    private static func readPlacement(
        _ reader: inout OASISReader,
        modal: inout OASISModalState,
        withTransform: Bool,
        cellNames: [String]
    ) throws -> [IRElement] {
        let infoByte = try reader.readByte()

        var cellName = modal.cellName ?? ""
        if infoByte & 0x80 != 0 {
            if infoByte & 0x40 != 0 {
                // N=1: cell-name reference number
                let refNum = try reader.readUnsignedInteger()
                cellName = try tableValue(cellNames, refNum: refNum, fallbackPrefix: "CELL_", context: "cell-name reference")
            } else {
                // N=0: inline cell name
                cellName = try reader.readAString()
            }
            modal.cellName = cellName
        }

        var transform = IRTransform.identity
        if withTransform {
            let mirrorX = (infoByte & 0x01) != 0
            var magnification = 1.0
            if infoByte & 0x04 != 0 {
                magnification = try reader.readReal()
            }
            var angle = 0.0
            if infoByte & 0x02 != 0 {
                angle = try reader.readReal()
            }
            transform = IRTransform(mirrorX: mirrorX, magnification: magnification, angle: angle)
        }

        if withTransform {
            if infoByte & 0x20 != 0 { modal.x = try reader.readSignedInteger() }
            if infoByte & 0x10 != 0 { modal.y = try reader.readSignedInteger() }
        } else {
            if infoByte & 0x20 != 0 { modal.x = try reader.readSignedInteger() }
            if infoByte & 0x10 != 0 { modal.y = try reader.readSignedInteger() }
        }

        // Repetition: a grid keeps its compact form as one array
        // reference; every other repetition kind expands into individual
        // placements — each repeated occurrence is real geometry, so
        // dropping the repetition would silently lose placements.
        let repBit: UInt8 = withTransform ? 0x08 : 0x08
        if infoByte & repBit != 0 {
            let rep = try readRepetitionWithReuse(&reader, modal: &modal)
            modal.lastRepetition = rep
            if case .grid(let cols, let rows, let colSpace, let rowSpace) = rep {
                let x = try checkedInt32(modal.x ?? 0, context: "placement x")
                let y = try checkedInt32(modal.y ?? 0, context: "placement y")
                let colOffset = try checkedMultiply(
                    checkedInt64(cols, context: "placement columns"),
                    checkedInt64(colSpace, context: "placement column spacing"),
                    context: "placement column offset"
                )
                let rowOffset = try checkedMultiply(
                    checkedInt64(rows, context: "placement rows"),
                    checkedInt64(rowSpace, context: "placement row spacing"),
                    context: "placement row offset"
                )
                let refPoints = [
                    IRPoint(x: x, y: y),
                    try checkedPoint(
                        x: checkedAdd(Int64(x), colOffset, context: "placement column reference x"),
                        y: Int64(y),
                        context: "placement column reference"
                    ),
                    try checkedPoint(
                        x: Int64(x),
                        y: checkedAdd(Int64(y), rowOffset, context: "placement row reference y"),
                        context: "placement row reference"
                    ),
                ]
                return [.arrayRef(IRArrayRef(
                    cellName: cellName,
                    transform: transform,
                    columns: try checkedInt16(cols, context: "placement columns"),
                    rows: try checkedInt16(rows, context: "placement rows"),
                    referencePoints: refPoints,
                    properties: []
                ))]
            }
            let x = try checkedInt32(modal.x ?? 0, context: "placement x")
            let y = try checkedInt32(modal.y ?? 0, context: "placement y")
            return try expand(
                .cellRef(IRCellRef(
                    cellName: cellName,
                    origin: IRPoint(x: x, y: y),
                    transform: transform,
                    properties: []
                )),
                repetition: rep
            )
        }

        let x = try checkedInt32(modal.x ?? 0, context: "placement x")
        let y = try checkedInt32(modal.y ?? 0, context: "placement y")

        return [.cellRef(IRCellRef(
            cellName: cellName,
            origin: IRPoint(x: x, y: y),
            transform: transform,
            properties: []
        ))]
    }

    // MARK: - TRAPEZOID

    private enum TrapezoidVariant {
        case both // record 23: both delta_a and delta_b
        case a    // record 24: only delta_a (delta_b = 0)
        case b    // record 25: only delta_b (delta_a = 0)
    }

    private static func readTrapezoid(_ reader: inout OASISReader, modal: inout OASISModalState, variant: TrapezoidVariant) throws -> [IRElement] {
        let infoByte = try reader.readByte()
        // Bit layout: O(7) W(6) H(5) X(4) Y(3) R(2) D(1) L(0)
        if infoByte & 0x01 != 0 { modal.layer = try reader.readUnsignedInteger() }
        if infoByte & 0x02 != 0 { modal.datatype = try reader.readUnsignedInteger() }
        if infoByte & 0x40 != 0 { modal.geometryW = try reader.readUnsignedInteger() }
        if infoByte & 0x20 != 0 { modal.geometryH = try reader.readUnsignedInteger() }

        var deltaA: Int64 = 0
        var deltaB: Int64 = 0
        switch variant {
        case .both:
            deltaA = try reader.readSignedInteger()
            deltaB = try reader.readSignedInteger()
        case .a:
            deltaA = try reader.readSignedInteger()
        case .b:
            deltaB = try reader.readSignedInteger()
        }

        if infoByte & 0x10 != 0 { modal.x = try reader.readSignedInteger() }
        if infoByte & 0x08 != 0 { modal.y = try reader.readSignedInteger() }

        let repetition = try readGeometryRepetitionIfPresent(infoByte: infoByte, reader: &reader, modal: &modal)

        let layer = try checkedInt16(modal.layer ?? 0, context: "trapezoid layer")
        let datatype = try checkedInt16(modal.datatype ?? 0, context: "trapezoid datatype")
        let x = try checkedInt32(modal.x ?? 0, context: "trapezoid x")
        let y = try checkedInt32(modal.y ?? 0, context: "trapezoid y")
        let w = try checkedInt32(modal.geometryW ?? 0, context: "trapezoid width")
        let h = try checkedInt32(modal.geometryH ?? 0, context: "trapezoid height")
        let isVertical = (infoByte & 0x80) != 0
        let da = try checkedInt32(deltaA, context: "trapezoid delta A")
        let db = try checkedInt32(deltaB, context: "trapezoid delta B")

        let points: [IRPoint]
        if isVertical {
            // Vertical trapezoid: top/bottom sides are slanted
            let topLeft = try checkedPoint(x: Int64(x), y: checkedAdd(Int64(y), positivePart(da), context: "trapezoid point"), context: "trapezoid point")
            points = [
                topLeft,
                try checkedPoint(x: checkedAdd(Int64(x), Int64(w), context: "trapezoid point"), y: checkedAdd(Int64(y), negativeMagnitude(da), context: "trapezoid point"), context: "trapezoid point"),
                try checkedPoint(x: checkedAdd(Int64(x), Int64(w), context: "trapezoid point"), y: checkedSubtract(checkedAdd(Int64(y), Int64(h), context: "trapezoid point"), negativeMagnitude(db), context: "trapezoid point"), context: "trapezoid point"),
                try checkedPoint(x: Int64(x), y: checkedSubtract(checkedAdd(Int64(y), Int64(h), context: "trapezoid point"), positivePart(db), context: "trapezoid point"), context: "trapezoid point"),
                topLeft,
            ]
        } else {
            // Horizontal trapezoid: left/right sides are slanted
            let topLeft = try checkedPoint(x: checkedAdd(Int64(x), positivePart(da), context: "trapezoid point"), y: Int64(y), context: "trapezoid point")
            points = [
                topLeft,
                try checkedPoint(x: checkedSubtract(checkedAdd(Int64(x), Int64(w), context: "trapezoid point"), positivePart(db), context: "trapezoid point"), y: Int64(y), context: "trapezoid point"),
                try checkedPoint(x: checkedSubtract(checkedAdd(Int64(x), Int64(w), context: "trapezoid point"), negativeMagnitude(db), context: "trapezoid point"), y: checkedAdd(Int64(y), Int64(h), context: "trapezoid point"), context: "trapezoid point"),
                try checkedPoint(x: checkedAdd(Int64(x), negativeMagnitude(da), context: "trapezoid point"), y: checkedAdd(Int64(y), Int64(h), context: "trapezoid point"), context: "trapezoid point"),
                topLeft,
            ]
        }

        return try expand(.boundary(IRBoundary(layer: layer, datatype: datatype, points: points, properties: [])), repetition: repetition)
    }

    // MARK: - CTRAPEZOID

    private static func readCTrapezoid(_ reader: inout OASISReader, modal: inout OASISModalState) throws -> [IRElement] {
        let infoByte = try reader.readByte()
        // Bit layout: T(7) W(6) H(5) X(4) Y(3) R(2) D(1) L(0)
        if infoByte & 0x01 != 0 { modal.layer = try reader.readUnsignedInteger() }
        if infoByte & 0x02 != 0 { modal.datatype = try reader.readUnsignedInteger() }
        if infoByte & 0x80 != 0 { modal.ctrapType = try reader.readUnsignedInteger() }
        if infoByte & 0x40 != 0 { modal.geometryW = try reader.readUnsignedInteger() }
        if infoByte & 0x20 != 0 { modal.geometryH = try reader.readUnsignedInteger() }
        if infoByte & 0x10 != 0 { modal.x = try reader.readSignedInteger() }
        if infoByte & 0x08 != 0 { modal.y = try reader.readSignedInteger() }

        let repetition = try readGeometryRepetitionIfPresent(infoByte: infoByte, reader: &reader, modal: &modal)

        let layer = try checkedInt16(modal.layer ?? 0, context: "ctrapezoid layer")
        let datatype = try checkedInt16(modal.datatype ?? 0, context: "ctrapezoid datatype")
        let ctrapTypeVal = try checkedInt(modal.ctrapType ?? 0, context: "ctrapezoid type")
        let x = try checkedInt32(modal.x ?? 0, context: "ctrapezoid x")
        let y = try checkedInt32(modal.y ?? 0, context: "ctrapezoid y")
        let w = try checkedInt32(modal.geometryW ?? 0, context: "ctrapezoid width")
        let h = try checkedInt32(modal.geometryH ?? 0, context: "ctrapezoid height")
        try validateCTrapezoidBounds(x: x, y: y, width: w, height: h)

        let points = try ctrapezoidPoints(type: ctrapTypeVal, x: x, y: y, w: w, h: h)
        return try expand(.boundary(IRBoundary(layer: layer, datatype: datatype, points: points, properties: [])), repetition: repetition)
    }

    // MARK: - CIRCLE

    private static func readCircle(_ reader: inout OASISReader, modal: inout OASISModalState) throws -> [IRElement] {
        let infoByte = try reader.readByte()
        // Bit layout: 0 0 R(5) X(4) Y(3) R(2) D(1) L(0) — R(5) = radius flag
        if infoByte & 0x01 != 0 { modal.layer = try reader.readUnsignedInteger() }
        if infoByte & 0x02 != 0 { modal.datatype = try reader.readUnsignedInteger() }
        if infoByte & 0x20 != 0 { modal.circleRadius = try reader.readUnsignedInteger() }
        if infoByte & 0x10 != 0 { modal.x = try reader.readSignedInteger() }
        if infoByte & 0x08 != 0 { modal.y = try reader.readSignedInteger() }

        let repetition = try readGeometryRepetitionIfPresent(infoByte: infoByte, reader: &reader, modal: &modal)

        let layer = try checkedInt16(modal.layer ?? 0, context: "circle layer")
        let datatype = try checkedInt16(modal.datatype ?? 0, context: "circle datatype")
        let cx = try checkedInt32(modal.x ?? 0, context: "circle x")
        let cy = try checkedInt32(modal.y ?? 0, context: "circle y")
        let radius = try checkedInt32(modal.circleRadius ?? 0, context: "circle radius")

        // Approximate circle with 64-point polygon (KLayout default)
        let segCount = 64
        var points: [IRPoint] = []
        points.reserveCapacity(segCount + 1)
        for i in 0..<segCount {
            let angle = 2.0 * Double.pi * Double(i) / Double(segCount)
            let dx = Int64(Double(radius) * cos(angle))
            let dy = Int64(Double(radius) * sin(angle))
            points.append(try checkedPoint(
                x: checkedAdd(Int64(cx), dx, context: "circle point x"),
                y: checkedAdd(Int64(cy), dy, context: "circle point y"),
                context: "circle point"
            ))
        }
        points.append(points[0]) // close polygon

        return try expand(.boundary(IRBoundary(layer: layer, datatype: datatype, points: points, properties: [])), repetition: repetition)
    }

    // MARK: - PROPERTY

    private static func readProperty(
        _ reader: inout OASISReader,
        modal: inout OASISModalState,
        propNames: [String]
    ) throws -> IRProperty {
        let infoByte = try reader.readByte()
        // OASIS spec layout: UUUU(7:4) V(3) C(2) T(1) S(0)

        let uuuu = Int((infoByte >> 4) & 0x0F)
        let vFlag = (infoByte & 0x08) != 0  // V: 1=reuse values from modal
        let cFlag = (infoByte & 0x04) != 0  // C: 1=name present in stream
        let tFlag = (infoByte & 0x02) != 0  // T: 1=name is reference number, 0=inline string

        // Read property name
        var propName = modal.lastPropertyName ?? ""
        if cFlag {
            if tFlag {
                // Reference number
                let refNum = try reader.readUnsignedInteger()
                propName = try tableValue(propNames, refNum: refNum, fallbackPrefix: "PROP_", context: "prop-name reference")
            } else {
                // Inline string
                propName = try reader.readAString()
            }
            modal.lastPropertyName = propName
        }

        // Read property values
        var values: [OASISPropertyValue] = []
        if !vFlag {
            // Values present in stream
            let valueCount: Int
            if uuuu == 15 {
                valueCount = try checkedCollectionElementCount(
                    try reader.readUnsignedInteger(),
                    context: "property value count"
                )
            } else {
                valueCount = uuuu
            }
            for _ in 0..<valueCount {
                values.append(try reader.readPropertyValue())
            }
            modal.lastPropertyValues = values
        } else {
            // Reuse values from modal
            values = modal.lastPropertyValues ?? []
        }

        return oasisPropertyToIR(name: propName, values: values)
    }

    private static func applyPropertyRepeat(modal: inout OASISModalState, elements: inout [IRElement]) {
        guard let name = modal.lastPropertyName, let values = modal.lastPropertyValues else { return }
        let irProp = oasisPropertyToIR(name: name, values: values)
        if !elements.isEmpty {
            attachProperty(&elements[elements.count - 1], irProp)
        }
    }

    private static func readTrailingProperties(
        _ reader: inout OASISReader,
        modal: inout OASISModalState,
        elements: inout [IRElement],
        range: Range<Int>,
        propNames: [String]
    ) throws {
        guard !range.isEmpty else { return }
        while reader.hasMore {
            let nextByte = try reader.peekByte()
            guard let nextType = OASISRecordType(rawValue: nextByte) else { break }
            switch nextType {
            case .property:
                _ = try reader.readByte()
                let property = try readProperty(&reader, modal: &modal, propNames: propNames)
                for index in range {
                    attachProperty(&elements[index], property)
                }
            case .propertyRepeat:
                _ = try reader.readByte()
                guard let name = modal.lastPropertyName, let values = modal.lastPropertyValues else { break }
                let irProp = oasisPropertyToIR(name: name, values: values)
                for index in range {
                    attachProperty(&elements[index], irProp)
                }
            default:
                return
            }
        }
    }

    private static func oasisPropertyToIR(name: String, values: [OASISPropertyValue]) -> IRProperty {
        // Convert property values to string representation
        let valueStr: String
        if values.count == 1 {
            switch values[0] {
            case .aString(let s): valueStr = s
            case .unsignedInteger(let v): valueStr = String(v)
            case .signedInteger(let v): valueStr = String(v)
            case .real(let v): valueStr = String(v)
            case .bString(let bytes): valueStr = bytes.map { String(format: "%02x", $0) }.joined()
            case .reference(let r): valueStr = "ref:\(r)"
            }
        } else if values.isEmpty {
            valueStr = ""
        } else {
            valueStr = values.map { v -> String in
                switch v {
                case .aString(let s): return s
                case .unsignedInteger(let n): return String(n)
                case .signedInteger(let n): return String(n)
                case .real(let d): return String(d)
                case .bString(let bytes): return bytes.map { String(format: "%02x", $0) }.joined()
                case .reference(let r): return "ref:\(r)"
                }
            }.joined(separator: ";")
        }
        // Use attribute 0 for OASIS properties (they use name-based keys, not numbered attributes)
        return IRProperty(attribute: 0, value: "\(name)=\(valueStr)")
    }

    private static func attachProperty(_ element: inout IRElement, _ prop: IRProperty) {
        switch element {
        case .boundary(var b):
            b.properties.append(prop)
            element = .boundary(b)
        case .path(var p):
            p.properties.append(prop)
            element = .path(p)
        case .cellRef(var r):
            r.properties.append(prop)
            element = .cellRef(r)
        case .arrayRef(var a):
            a.properties.append(prop)
            element = .arrayRef(a)
        case .text(var t):
            t.properties.append(prop)
            element = .text(t)
        }
    }

    // MARK: - Repetition with Reuse

    private static func readRepetitionWithReuse(_ reader: inout OASISReader, modal: inout OASISModalState) throws -> OASISRepetition {
        let nextByte = try reader.peekByte()
        // Type 0 = reuse previous repetition
        if nextByte == 0 {
            let offset = reader.currentOffset
            _ = try reader.readByte() // consume the type-0 byte
            guard let lastRepetition = modal.lastRepetition else {
                throw OASISError.invalidRepetitionType(offset: offset, typeCode: 0)
            }
            return lastRepetition
        }
        return try reader.readRepetition()
    }

    // MARK: - Helpers

    private static let maxDecodedCollectionElements = 1_000_000
    private static let maxExpandedRepetitionElements = 1_000_000

    private static func checkedInt(_ value: UInt64, context: String) throws -> Int {
        guard value <= UInt64(Int.max) else {
            throw OASISError.numericOverflow(context: context, value: String(value))
        }
        return Int(value)
    }

    private static func checkedCollectionElementCount(_ value: UInt64, context: String) throws -> Int {
        let count = try checkedInt(value, context: context)
        guard count <= maxDecodedCollectionElements else {
            throw OASISError.numericOverflow(
                context: context,
                value: "\(value) exceeds supported collection limit \(maxDecodedCollectionElements)"
            )
        }
        return count
    }

    private static func checkedTableIndex(_ value: UInt64, context: String) throws -> Int {
        try checkedCollectionElementCount(value, context: context)
    }

    private static func appendPlaceholders(to table: inout [String], through index: Int) {
        while table.count <= index {
            table.append("")
        }
    }

    private static func tableValue(
        _ table: [String],
        refNum: UInt64,
        fallbackPrefix: String,
        context: String
    ) throws -> String {
        _ = fallbackPrefix
        let index = try checkedTableIndex(refNum, context: context)
        guard index < table.count, !table[index].isEmpty else {
            throw OASISError.unresolvedReference(context: context, refNum: refNum)
        }
        return table[index]
    }

    private static func checkedInt16(_ value: UInt64, context: String) throws -> Int16 {
        guard value <= UInt64(Int16.max) else {
            throw OASISError.numericOverflow(context: context, value: String(value))
        }
        return Int16(value)
    }

    private static func checkedInt32(_ value: UInt64, context: String) throws -> Int32 {
        guard value <= UInt64(Int32.max) else {
            throw OASISError.numericOverflow(context: context, value: String(value))
        }
        return Int32(value)
    }

    private static func checkedInt32(_ value: Int64, context: String) throws -> Int32 {
        guard value >= Int64(Int32.min), value <= Int64(Int32.max) else {
            throw OASISError.numericOverflow(context: context, value: String(value))
        }
        return Int32(value)
    }

    private static func checkedInt64(_ value: UInt64, context: String) throws -> Int64 {
        guard value <= UInt64(Int64.max) else {
            throw OASISError.numericOverflow(context: context, value: String(value))
        }
        return Int64(value)
    }

    private static func checkedAdd(_ lhs: Int64, _ rhs: Int64, context: String) throws -> Int64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw OASISError.numericOverflow(context: context, value: "\(lhs)+\(rhs)")
        }
        return result
    }

    private static func checkedSubtract(_ lhs: Int64, _ rhs: Int64, context: String) throws -> Int64 {
        let (result, overflow) = lhs.subtractingReportingOverflow(rhs)
        guard !overflow else {
            throw OASISError.numericOverflow(context: context, value: "\(lhs)-\(rhs)")
        }
        return result
    }

    private static func checkedMultiply(_ lhs: Int64, _ rhs: Int64, context: String) throws -> Int64 {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else {
            throw OASISError.numericOverflow(context: context, value: "\(lhs)*\(rhs)")
        }
        return result
    }

    private static func checkedPoint(x: Int64, y: Int64, context: String) throws -> IRPoint {
        IRPoint(
            x: try checkedInt32(x, context: "\(context) x"),
            y: try checkedInt32(y, context: "\(context) y")
        )
    }

    private static func rectanglePoints(
        x: Int32,
        y: Int32,
        width: Int32,
        height: Int32,
        context: String
    ) throws -> [IRPoint] {
        let maxX = try checkedAdd(Int64(x), Int64(width), context: "\(context) max x")
        let maxY = try checkedAdd(Int64(y), Int64(height), context: "\(context) max y")
        let topRight = try checkedPoint(x: maxX, y: Int64(y), context: context)
        let bottomRight = try checkedPoint(x: maxX, y: maxY, context: context)
        let bottomLeft = try checkedPoint(x: Int64(x), y: maxY, context: context)
        let topLeft = IRPoint(x: x, y: y)
        return [topLeft, topRight, bottomRight, bottomLeft, topLeft]
    }

    private static func checkedRepetitionElementCount(_ count: UInt64, context: String) throws -> Int {
        guard count <= UInt64(maxExpandedRepetitionElements) else {
            throw OASISError.numericOverflow(
                context: context,
                value: "\(count) exceeds supported expansion limit \(maxExpandedRepetitionElements)"
            )
        }
        return try checkedInt(count, context: context)
    }

    private static func checkedRepetitionElementCount(
        _ columns: UInt64,
        _ rows: UInt64,
        context: String
    ) throws -> Int {
        let (count, overflow) = columns.multipliedReportingOverflow(by: rows)
        guard !overflow else {
            throw OASISError.numericOverflow(context: context, value: "\(columns)*\(rows)")
        }
        return try checkedRepetitionElementCount(count, context: context)
    }

    private static func positivePart(_ value: Int32) -> Int64 {
        value > 0 ? Int64(value) : 0
    }

    private static func negativeMagnitude(_ value: Int32) -> Int64 {
        value < 0 ? -Int64(value) : 0
    }

    private static func validateCTrapezoidBounds(
        x: Int32,
        y: Int32,
        width: Int32,
        height: Int32
    ) throws {
        let maxDelta = max(Int64(width), Int64(height))
        _ = try checkedPoint(
            x: checkedSubtract(Int64(x), maxDelta, context: "ctrapezoid bounds min x"),
            y: checkedSubtract(Int64(y), maxDelta, context: "ctrapezoid bounds min y"),
            context: "ctrapezoid bounds"
        )
        _ = try checkedPoint(
            x: checkedAdd(Int64(x), maxDelta, context: "ctrapezoid bounds max x"),
            y: checkedAdd(Int64(y), maxDelta, context: "ctrapezoid bounds max y"),
            context: "ctrapezoid bounds"
        )
    }

    private static func irPathType(from extensionScheme: UInt64) -> IRPathType {
        // OASIS extension scheme is a packed bitfield:
        // Bits 1:0 = start extension type (0=flush, 1=halfwidth, 2=explicit)
        // Bits 3:2 = end extension type (same encoding)
        // Use start extension type as representative
        let startExt = extensionScheme & 0x03
        switch startExt {
        case 0: return .flush
        case 1: return .halfWidthExtend
        default: return .flush
        }
    }
}
