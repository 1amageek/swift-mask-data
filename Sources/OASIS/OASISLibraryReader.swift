import Foundation
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
        let unitReal = try reader.readReal()
        let dbuPerMicron = 1.0 / unitReal
        let units = IRUnits(dbuPerMicron: dbuPerMicron)
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
                return IRLibrary(name: name, units: units, cells: cells)
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
                while propStrings.count <= Int(refNum) { propStrings.append("") }
                propStrings[Int(refNum)] = name
                if libraryName.isEmpty { libraryName = name }
            case .cellname:
                let name = try reader.readAString()
                cellNames.append(name)
            case .cellnameRef:
                let refNum = try reader.readUnsignedInteger()
                let name = try reader.readAString()
                while cellNames.count <= Int(refNum) { cellNames.append("") }
                cellNames[Int(refNum)] = name
            case .textstring:
                textStrings.append(try reader.readAString())
            case .textstringRef:
                let refNum = try reader.readUnsignedInteger()
                let name = try reader.readAString()
                while textStrings.count <= Int(refNum) { textStrings.append("") }
                textStrings[Int(refNum)] = name
            case .propname:
                propNames.append(try reader.readAString())
            case .propnameRef:
                let refNum = try reader.readUnsignedInteger()
                let name = try reader.readAString()
                while propNames.count <= Int(refNum) { propNames.append("") }
                propNames[Int(refNum)] = name
            case .cell:
                let cellName = try reader.readAString()
                let cell = try readCellContents(&reader, name: cellName, cellNames: cellNames, textStrings: textStrings, propNames: propNames)
                cells.append(cell)
            case .cellRef:
                let refNum = try reader.readUnsignedInteger()
                let cellName = Int(refNum) < cellNames.count ? cellNames[Int(refNum)] : "CELL_\(refNum)"
                let cell = try readCellContents(&reader, name: cellName, cellNames: cellNames, textStrings: textStrings, propNames: propNames)
                cells.append(cell)
            case .cblock:
                try reader.handleCBlock()
            default:
                continue
            }
        }

        let name = libraryName.isEmpty ? "OASIS" : libraryName
        return IRLibrary(name: name, units: units, cells: cells)
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
                break
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
                let element = try readRectangle(&reader, modal: &modal)
                elements.append(element)
                try readTrailingProperties(&reader, modal: &modal, element: &elements[elements.count - 1], propNames: propNames)
            case .polygon:
                _ = try reader.readByte()
                let element = try readPolygon(&reader, modal: &modal)
                elements.append(element)
                try readTrailingProperties(&reader, modal: &modal, element: &elements[elements.count - 1], propNames: propNames)
            case .path:
                _ = try reader.readByte()
                let element = try readPath(&reader, modal: &modal)
                elements.append(element)
                try readTrailingProperties(&reader, modal: &modal, element: &elements[elements.count - 1], propNames: propNames)
            case .text:
                _ = try reader.readByte()
                let element = try readText(&reader, modal: &modal, textStrings: textStrings)
                elements.append(element)
                try readTrailingProperties(&reader, modal: &modal, element: &elements[elements.count - 1], propNames: propNames)
            case .placement:
                _ = try reader.readByte()
                let element = try readPlacement(&reader, modal: &modal, withTransform: false, cellNames: cellNames)
                elements.append(element)
                try readTrailingProperties(&reader, modal: &modal, element: &elements[elements.count - 1], propNames: propNames)
            case .placementT:
                _ = try reader.readByte()
                let element = try readPlacement(&reader, modal: &modal, withTransform: true, cellNames: cellNames)
                elements.append(element)
                try readTrailingProperties(&reader, modal: &modal, element: &elements[elements.count - 1], propNames: propNames)
            case .trapezoid:
                _ = try reader.readByte()
                let element = try readTrapezoid(&reader, modal: &modal, variant: .both)
                elements.append(element)
                try readTrailingProperties(&reader, modal: &modal, element: &elements[elements.count - 1], propNames: propNames)
            case .trapezoidA:
                _ = try reader.readByte()
                let element = try readTrapezoid(&reader, modal: &modal, variant: .a)
                elements.append(element)
                try readTrailingProperties(&reader, modal: &modal, element: &elements[elements.count - 1], propNames: propNames)
            case .trapezoidB:
                _ = try reader.readByte()
                let element = try readTrapezoid(&reader, modal: &modal, variant: .b)
                elements.append(element)
                try readTrailingProperties(&reader, modal: &modal, element: &elements[elements.count - 1], propNames: propNames)
            case .ctrapezoid:
                _ = try reader.readByte()
                let element = try readCTrapezoid(&reader, modal: &modal)
                elements.append(element)
                try readTrailingProperties(&reader, modal: &modal, element: &elements[elements.count - 1], propNames: propNames)
            case .circle:
                _ = try reader.readByte()
                let element = try readCircle(&reader, modal: &modal)
                elements.append(element)
                try readTrailingProperties(&reader, modal: &modal, element: &elements[elements.count - 1], propNames: propNames)
            case .property:
                _ = try reader.readByte()
                try readProperty(&reader, modal: &modal, elements: &elements, propNames: propNames)
            case .propertyRepeat:
                _ = try reader.readByte()
                applyPropertyRepeat(modal: &modal, elements: &elements)
            case .cblock:
                _ = try reader.readByte()
                try reader.handleCBlock()
            case .pad:
                _ = try reader.readByte()
            default:
                _ = try reader.readByte()
            }
        }

        return IRCell(name: name, elements: elements)
    }

    // MARK: - RECTANGLE

    private static func readRectangle(_ reader: inout OASISReader, modal: inout OASISModalState) throws -> IRElement {
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

        if infoByte & 0x04 != 0 {
            modal.lastRepetition = try readRepetitionWithReuse(&reader, modal: &modal)
        }

        let layer = Int16(modal.layer ?? 0)
        let datatype = Int16(modal.datatype ?? 0)
        let x = Int32(modal.x ?? 0)
        let y = Int32(modal.y ?? 0)
        let w = Int32(modal.geometryW ?? 0)
        let h = Int32(modal.geometryH ?? 0)

        let points = [
            IRPoint(x: x, y: y),
            IRPoint(x: x + w, y: y),
            IRPoint(x: x + w, y: y + h),
            IRPoint(x: x, y: y + h),
            IRPoint(x: x, y: y),
        ]

        return .boundary(IRBoundary(layer: layer, datatype: datatype, points: points, properties: []))
    }

    // MARK: - POLYGON

    private static func readPolygon(_ reader: inout OASISReader, modal: inout OASISModalState) throws -> IRElement {
        let infoByte = try reader.readByte()
        if infoByte & 0x01 != 0 { modal.layer = try reader.readUnsignedInteger() }
        if infoByte & 0x02 != 0 { modal.datatype = try reader.readUnsignedInteger() }

        var deltas: [IRPoint] = []
        if infoByte & 0x20 != 0 {
            deltas = try reader.readPointList()
        }

        if infoByte & 0x10 != 0 { modal.x = try reader.readSignedInteger() }
        if infoByte & 0x08 != 0 { modal.y = try reader.readSignedInteger() }

        if infoByte & 0x04 != 0 {
            modal.lastRepetition = try readRepetitionWithReuse(&reader, modal: &modal)
        }

        let layer = Int16(modal.layer ?? 0)
        let datatype = Int16(modal.datatype ?? 0)
        let originX = Int32(modal.x ?? 0)
        let originY = Int32(modal.y ?? 0)

        var points: [IRPoint] = [IRPoint(x: originX, y: originY)]
        var cx = originX
        var cy = originY
        for delta in deltas {
            cx += delta.x
            cy += delta.y
            points.append(IRPoint(x: cx, y: cy))
        }
        points.append(IRPoint(x: originX, y: originY))

        return .boundary(IRBoundary(layer: layer, datatype: datatype, points: points, properties: []))
    }

    // MARK: - PATH

    private static func readPath(_ reader: inout OASISReader, modal: inout OASISModalState) throws -> IRElement {
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

        if infoByte & 0x04 != 0 {
            modal.lastRepetition = try readRepetitionWithReuse(&reader, modal: &modal)
        }

        let layer = Int16(modal.layer ?? 0)
        let datatype = Int16(modal.datatype ?? 0)
        let halfwidth = modal.pathHalfwidth ?? 0
        let width = Int32(halfwidth) * 2
        let originX = Int32(modal.x ?? 0)
        let originY = Int32(modal.y ?? 0)

        var points: [IRPoint] = [IRPoint(x: originX, y: originY)]
        var cx = originX
        var cy = originY
        for delta in deltas {
            cx += delta.x
            cy += delta.y
            points.append(IRPoint(x: cx, y: cy))
        }

        return .path(IRPath(layer: layer, datatype: datatype, pathType: pathType, width: width, points: points, properties: []))
    }

    // MARK: - TEXT

    private static func readText(_ reader: inout OASISReader, modal: inout OASISModalState, textStrings: [String]) throws -> IRElement {
        let infoByte = try reader.readByte()

        var textString = modal.textString ?? ""
        if infoByte & 0x40 != 0 {
            // C bit: check if N bit indicates reference
            if infoByte & 0x20 != 0 {
                // N=1: text-string reference number
                let refNum = try reader.readUnsignedInteger()
                textString = Int(refNum) < textStrings.count ? textStrings[Int(refNum)] : ""
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

        if infoByte & 0x04 != 0 {
            modal.lastRepetition = try readRepetitionWithReuse(&reader, modal: &modal)
        }

        let layer = Int16(modal.textlayer ?? 0)
        let texttype = Int16(modal.texttype ?? 0)
        let x = Int32(modal.x ?? 0)
        let y = Int32(modal.y ?? 0)

        return .text(IRText(
            layer: layer,
            texttype: texttype,
            transform: .identity,
            position: IRPoint(x: x, y: y),
            string: textString,
            properties: []
        ))
    }

    // MARK: - PLACEMENT

    private static func readPlacement(
        _ reader: inout OASISReader,
        modal: inout OASISModalState,
        withTransform: Bool,
        cellNames: [String]
    ) throws -> IRElement {
        let infoByte = try reader.readByte()

        var cellName = modal.cellName ?? ""
        if infoByte & 0x80 != 0 {
            if infoByte & 0x40 != 0 {
                // N=1: cell-name reference number
                let refNum = try reader.readUnsignedInteger()
                cellName = Int(refNum) < cellNames.count ? cellNames[Int(refNum)] : "CELL_\(refNum)"
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

        // Repetition
        let repBit: UInt8 = withTransform ? 0x08 : 0x08
        if infoByte & repBit != 0 {
            let rep = try readRepetitionWithReuse(&reader, modal: &modal)
            modal.lastRepetition = rep
            if case .grid(let cols, let rows, let colSpace, let rowSpace) = rep {
                let x = Int32(modal.x ?? 0)
                let y = Int32(modal.y ?? 0)
                let refPoints = [
                    IRPoint(x: x, y: y),
                    IRPoint(x: x + Int32(cols) * Int32(colSpace), y: y),
                    IRPoint(x: x, y: y + Int32(rows) * Int32(rowSpace)),
                ]
                return .arrayRef(IRArrayRef(
                    cellName: cellName,
                    transform: transform,
                    columns: Int16(cols),
                    rows: Int16(rows),
                    referencePoints: refPoints,
                    properties: []
                ))
            }
        }

        let x = Int32(modal.x ?? 0)
        let y = Int32(modal.y ?? 0)

        return .cellRef(IRCellRef(
            cellName: cellName,
            origin: IRPoint(x: x, y: y),
            transform: transform,
            properties: []
        ))
    }

    // MARK: - TRAPEZOID

    private enum TrapezoidVariant {
        case both // record 23: both delta_a and delta_b
        case a    // record 24: only delta_a (delta_b = 0)
        case b    // record 25: only delta_b (delta_a = 0)
    }

    private static func readTrapezoid(_ reader: inout OASISReader, modal: inout OASISModalState, variant: TrapezoidVariant) throws -> IRElement {
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

        if infoByte & 0x04 != 0 {
            modal.lastRepetition = try readRepetitionWithReuse(&reader, modal: &modal)
        }

        let layer = Int16(modal.layer ?? 0)
        let datatype = Int16(modal.datatype ?? 0)
        let x = Int32(modal.x ?? 0)
        let y = Int32(modal.y ?? 0)
        let w = Int32(modal.geometryW ?? 0)
        let h = Int32(modal.geometryH ?? 0)
        let isVertical = (infoByte & 0x80) != 0
        let da = Int32(deltaA)
        let db = Int32(deltaB)

        let points: [IRPoint]
        if isVertical {
            // Vertical trapezoid: top/bottom sides are slanted
            points = [
                IRPoint(x: x, y: y + (da > 0 ? da : 0)),
                IRPoint(x: x + w, y: y + (da < 0 ? -da : 0)),
                IRPoint(x: x + w, y: y + h - (db < 0 ? -db : 0)),
                IRPoint(x: x, y: y + h - (db > 0 ? db : 0)),
                IRPoint(x: x, y: y + (da > 0 ? da : 0)),
            ]
        } else {
            // Horizontal trapezoid: left/right sides are slanted
            points = [
                IRPoint(x: x + (da > 0 ? da : 0), y: y),
                IRPoint(x: x + w - (db > 0 ? db : 0), y: y),
                IRPoint(x: x + w - (db < 0 ? -db : 0), y: y + h),
                IRPoint(x: x + (da < 0 ? -da : 0), y: y + h),
                IRPoint(x: x + (da > 0 ? da : 0), y: y),
            ]
        }

        return .boundary(IRBoundary(layer: layer, datatype: datatype, points: points, properties: []))
    }

    // MARK: - CTRAPEZOID

    private static func readCTrapezoid(_ reader: inout OASISReader, modal: inout OASISModalState) throws -> IRElement {
        let infoByte = try reader.readByte()
        // Bit layout: T(7) W(6) H(5) X(4) Y(3) R(2) D(1) L(0)
        if infoByte & 0x01 != 0 { modal.layer = try reader.readUnsignedInteger() }
        if infoByte & 0x02 != 0 { modal.datatype = try reader.readUnsignedInteger() }
        if infoByte & 0x80 != 0 { modal.ctrapType = try reader.readUnsignedInteger() }
        if infoByte & 0x40 != 0 { modal.geometryW = try reader.readUnsignedInteger() }
        if infoByte & 0x20 != 0 { modal.geometryH = try reader.readUnsignedInteger() }
        if infoByte & 0x10 != 0 { modal.x = try reader.readSignedInteger() }
        if infoByte & 0x08 != 0 { modal.y = try reader.readSignedInteger() }

        if infoByte & 0x04 != 0 {
            modal.lastRepetition = try readRepetitionWithReuse(&reader, modal: &modal)
        }

        let layer = Int16(modal.layer ?? 0)
        let datatype = Int16(modal.datatype ?? 0)
        let ctrapTypeVal = Int(modal.ctrapType ?? 0)
        let x = Int32(modal.x ?? 0)
        let y = Int32(modal.y ?? 0)
        let w = Int32(modal.geometryW ?? 0)
        let h = Int32(modal.geometryH ?? 0)

        let points = try ctrapezoidPoints(type: ctrapTypeVal, x: x, y: y, w: w, h: h)
        return .boundary(IRBoundary(layer: layer, datatype: datatype, points: points, properties: []))
    }

    // MARK: - CIRCLE

    private static func readCircle(_ reader: inout OASISReader, modal: inout OASISModalState) throws -> IRElement {
        let infoByte = try reader.readByte()
        // Bit layout: 0 0 R(5) X(4) Y(3) R(2) D(1) L(0) — R(5) = radius flag
        if infoByte & 0x01 != 0 { modal.layer = try reader.readUnsignedInteger() }
        if infoByte & 0x02 != 0 { modal.datatype = try reader.readUnsignedInteger() }
        if infoByte & 0x20 != 0 { modal.circleRadius = try reader.readUnsignedInteger() }
        if infoByte & 0x10 != 0 { modal.x = try reader.readSignedInteger() }
        if infoByte & 0x08 != 0 { modal.y = try reader.readSignedInteger() }

        if infoByte & 0x04 != 0 {
            modal.lastRepetition = try readRepetitionWithReuse(&reader, modal: &modal)
        }

        let layer = Int16(modal.layer ?? 0)
        let datatype = Int16(modal.datatype ?? 0)
        let cx = Int32(modal.x ?? 0)
        let cy = Int32(modal.y ?? 0)
        let radius = Int32(modal.circleRadius ?? 0)

        // Approximate circle with 64-point polygon (KLayout default)
        let segCount = 64
        var points: [IRPoint] = []
        points.reserveCapacity(segCount + 1)
        for i in 0..<segCount {
            let angle = 2.0 * Double.pi * Double(i) / Double(segCount)
            let px = cx + Int32(Double(radius) * cos(angle))
            let py = cy + Int32(Double(radius) * sin(angle))
            points.append(IRPoint(x: px, y: py))
        }
        points.append(points[0]) // close polygon

        return .boundary(IRBoundary(layer: layer, datatype: datatype, points: points, properties: []))
    }

    // MARK: - PROPERTY

    private static func readProperty(
        _ reader: inout OASISReader,
        modal: inout OASISModalState,
        elements: inout [IRElement],
        propNames: [String]
    ) throws {
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
                propName = Int(refNum) < propNames.count ? propNames[Int(refNum)] : "PROP_\(refNum)"
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
                valueCount = Int(try reader.readUnsignedInteger())
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

        // Convert to IRProperty and attach to last element
        let irProp = oasisPropertyToIR(name: propName, values: values)
        if !elements.isEmpty {
            attachProperty(&elements[elements.count - 1], irProp)
        }
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
        element: inout IRElement,
        propNames: [String]
    ) throws {
        while reader.hasMore {
            let nextByte = try reader.peekByte()
            guard let nextType = OASISRecordType(rawValue: nextByte) else { break }
            switch nextType {
            case .property:
                _ = try reader.readByte()
                var elements = [element]
                try readProperty(&reader, modal: &modal, elements: &elements, propNames: propNames)
                element = elements[0]
            case .propertyRepeat:
                _ = try reader.readByte()
                guard let name = modal.lastPropertyName, let values = modal.lastPropertyValues else { break }
                let irProp = oasisPropertyToIR(name: name, values: values)
                attachProperty(&element, irProp)
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
            _ = try reader.readByte() // consume the type-0 byte
            return modal.lastRepetition ?? .uniformRow(count: 2, spacing: 0)
        }
        return try reader.readRepetition()
    }

    // MARK: - Helpers

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
