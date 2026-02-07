import Foundation
import LayoutIR

/// Converts GDSII binary data to an IRLibrary.
public enum GDSLibraryReader {

    public static func read(_ data: Data, options: GDSReadOptions = .default) throws -> IRLibrary {
        var reader = GDSRecordReader(data: data)
        return try readLibrary(&reader, options: options)
    }

    // MARK: - Library

    private static func readLibrary(_ r: inout GDSRecordReader, options: GDSReadOptions) throws -> IRLibrary {
        // HEADER
        let header = try r.readRecord()
        guard header.recordType == .header else {
            throw GDSError.unexpectedRecord(got: header.recordType, expected: .header, offset: 0)
        }

        // BGNLIB
        let bgnlib = try r.readRecord()
        guard bgnlib.recordType == .bgnlib else {
            throw GDSError.unexpectedRecord(got: bgnlib.recordType, expected: .bgnlib, offset: r.currentOffset)
        }

        // LIBNAME
        let libnameRec = try r.readRecord()
        guard libnameRec.recordType == .libname else {
            throw GDSError.missingRequiredRecord(.libname, context: "after BGNLIB")
        }
        guard case .string(let libName) = libnameRec.payload else {
            throw GDSError.missingRequiredRecord(.libname, context: "invalid payload")
        }

        // UNITS
        let unitsRec = try r.readRecord()
        guard unitsRec.recordType == .units else {
            throw GDSError.missingRequiredRecord(.units, context: "after LIBNAME")
        }
        let units: IRUnits
        if case .real8(let values) = unitsRec.payload, values.count >= 2 {
            let userUnitsPerDBU = values[0]
            let metersPerDBU = values[1]
            // dbuPerMicron = 1e-6 / metersPerDBU
            let dbuPerMicron = 1e-6 / metersPerDBU
            _ = userUnitsPerDBU // stored in GDSII but derived from dbuPerMicron
            units = IRUnits(dbuPerMicron: dbuPerMicron)
        } else {
            units = .default
        }

        // Read structures until ENDLIB
        var cells: [IRCell] = []
        while r.hasMore {
            let nextType = try r.peekRecordType()
            if nextType == .endlib {
                _ = try r.readRecord()
                break
            } else if nextType == .bgnstr {
                let cell = try readCell(&r, options: options)
                cells.append(cell)
            } else {
                // Skip unknown top-level records
                _ = try r.readRecord()
            }
        }

        return IRLibrary(name: libName, units: units, cells: cells)
    }

    // MARK: - Cell

    private static func readCell(_ r: inout GDSRecordReader, options: GDSReadOptions) throws -> IRCell {
        // BGNSTR
        _ = try r.readRecord()

        // STRNAME
        let nameRec = try r.readRecord()
        guard nameRec.recordType == .strname else {
            throw GDSError.missingRequiredRecord(.strname, context: "after BGNSTR")
        }
        guard case .string(let cellName) = nameRec.payload else {
            throw GDSError.missingRequiredRecord(.strname, context: "invalid payload")
        }

        // Read elements until ENDSTR
        var elements: [IRElement] = []
        while r.hasMore {
            let nextType = try r.peekRecordType()
            if nextType == .endstr {
                _ = try r.readRecord()
                break
            }
            if let element = try readElement(&r, options: options) {
                elements.append(element)
            }
        }

        return IRCell(name: cellName, elements: elements)
    }

    // MARK: - Elements

    private static func readElement(_ r: inout GDSRecordReader, options: GDSReadOptions) throws -> IRElement? {
        let startRec = try r.readRecord()

        switch startRec.recordType {
        case .boundary:
            return try .boundary(readBoundary(&r))
        case .path:
            return try .path(readPath(&r))
        case .sref:
            return try .cellRef(readCellRef(&r))
        case .aref:
            return try .arrayRef(readArrayRef(&r))
        case .text:
            return try .text(readText(&r))
        case .box:
            switch options.boxMode {
            case .asBoundary:
                return try .boundary(readBox(&r))
            case .ignore:
                try skipToEndel(&r)
                return nil
            }
        case .node:
            // NODE is a connectivity hint, not visible geometry
            try skipToEndel(&r)
            return nil
        default:
            // Unknown element: skip until ENDEL
            try skipToEndel(&r)
            return nil
        }
    }

    private static func readBoundary(_ r: inout GDSRecordReader) throws -> IRBoundary {
        var layer: Int16 = 0
        var datatype: Int16 = 0
        var points: [IRPoint] = []
        var properties: [IRProperty] = []

        while r.hasMore {
            let nextType = try r.peekRecordType()
            if nextType == .endel {
                _ = try r.readRecord()
                break
            }
            let rec = try r.readRecord()
            switch rec.recordType {
            case .layer:
                if case .int16(let v) = rec.payload, let first = v.first { layer = first }
            case .datatype:
                if case .int16(let v) = rec.payload, let first = v.first { datatype = first }
            case .xy:
                // Multi-XY: append points from consecutive XY records
                points.append(contentsOf: extractPoints(rec.payload))
            case .propattr:
                let prop = try readProperty(rec, r: &r)
                properties.append(prop)
            default:
                break
            }
        }

        return IRBoundary(layer: layer, datatype: datatype, points: points, properties: properties)
    }

    private static func readPath(_ r: inout GDSRecordReader) throws -> IRPath {
        var layer: Int16 = 0
        var datatype: Int16 = 0
        var pathType: IRPathType = .flush
        var width: Int32 = 0
        var points: [IRPoint] = []
        var properties: [IRProperty] = []
        var beginExtension: Int32?
        var endExtension: Int32?

        while r.hasMore {
            let nextType = try r.peekRecordType()
            if nextType == .endel {
                _ = try r.readRecord()
                break
            }
            let rec = try r.readRecord()
            switch rec.recordType {
            case .layer:
                if case .int16(let v) = rec.payload, let first = v.first { layer = first }
            case .datatype:
                if case .int16(let v) = rec.payload, let first = v.first { datatype = first }
            case .pathtype:
                if case .int16(let v) = rec.payload, let first = v.first {
                    pathType = IRPathType(rawValue: first) ?? .flush
                }
            case .width:
                if case .int32(let v) = rec.payload, let first = v.first { width = first }
            case .bgnextn:
                if case .int32(let v) = rec.payload, let first = v.first { beginExtension = first }
            case .endextn:
                if case .int32(let v) = rec.payload, let first = v.first { endExtension = first }
            case .xy:
                // Multi-XY: append points from consecutive XY records
                points.append(contentsOf: extractPoints(rec.payload))
            case .propattr:
                let prop = try readProperty(rec, r: &r)
                properties.append(prop)
            default:
                break
            }
        }

        return IRPath(
            layer: layer, datatype: datatype, pathType: pathType,
            width: width, points: points, properties: properties,
            beginExtension: beginExtension, endExtension: endExtension
        )
    }

    private static func readCellRef(_ r: inout GDSRecordReader) throws -> IRCellRef {
        var cellName = ""
        var origin = IRPoint.zero
        var transform = IRTransform.identity
        var properties: [IRProperty] = []

        while r.hasMore {
            let nextType = try r.peekRecordType()
            if nextType == .endel {
                _ = try r.readRecord()
                break
            }
            let rec = try r.readRecord()
            switch rec.recordType {
            case .sname:
                if case .string(let s) = rec.payload { cellName = s }
            case .strans:
                transform = readTransformStart(rec.payload, transform: transform)
            case .mag:
                if case .real8(let v) = rec.payload, let first = v.first {
                    transform = IRTransform(mirrorX: transform.mirrorX, magnification: first, angle: transform.angle)
                }
            case .angle:
                if case .real8(let v) = rec.payload, let first = v.first {
                    transform = IRTransform(mirrorX: transform.mirrorX, magnification: transform.magnification, angle: first)
                }
            case .xy:
                let pts = extractPoints(rec.payload)
                if let first = pts.first { origin = first }
            case .propattr:
                let prop = try readProperty(rec, r: &r)
                properties.append(prop)
            default:
                break
            }
        }

        return IRCellRef(cellName: cellName, origin: origin, transform: transform, properties: properties)
    }

    private static func readArrayRef(_ r: inout GDSRecordReader) throws -> IRArrayRef {
        var cellName = ""
        var transform = IRTransform.identity
        var columns: Int16 = 0
        var rows: Int16 = 0
        var referencePoints: [IRPoint] = []
        var properties: [IRProperty] = []

        while r.hasMore {
            let nextType = try r.peekRecordType()
            if nextType == .endel {
                _ = try r.readRecord()
                break
            }
            let rec = try r.readRecord()
            switch rec.recordType {
            case .sname:
                if case .string(let s) = rec.payload { cellName = s }
            case .strans:
                transform = readTransformStart(rec.payload, transform: transform)
            case .mag:
                if case .real8(let v) = rec.payload, let first = v.first {
                    transform = IRTransform(mirrorX: transform.mirrorX, magnification: first, angle: transform.angle)
                }
            case .angle:
                if case .real8(let v) = rec.payload, let first = v.first {
                    transform = IRTransform(mirrorX: transform.mirrorX, magnification: transform.magnification, angle: first)
                }
            case .colrow:
                if case .int16(let v) = rec.payload, v.count >= 2 {
                    columns = v[0]
                    rows = v[1]
                }
            case .xy:
                // Multi-XY: append points from consecutive XY records
                referencePoints.append(contentsOf: extractPoints(rec.payload))
            case .propattr:
                let prop = try readProperty(rec, r: &r)
                properties.append(prop)
            default:
                break
            }
        }

        return IRArrayRef(cellName: cellName, transform: transform, columns: columns, rows: rows, referencePoints: referencePoints, properties: properties)
    }

    private static func readText(_ r: inout GDSRecordReader) throws -> IRText {
        var layer: Int16 = 0
        var texttype: Int16 = 0
        var transform = IRTransform.identity
        var position = IRPoint.zero
        var string = ""
        var properties: [IRProperty] = []

        while r.hasMore {
            let nextType = try r.peekRecordType()
            if nextType == .endel {
                _ = try r.readRecord()
                break
            }
            let rec = try r.readRecord()
            switch rec.recordType {
            case .layer:
                if case .int16(let v) = rec.payload, let first = v.first { layer = first }
            case .texttype:
                if case .int16(let v) = rec.payload, let first = v.first { texttype = first }
            case .strans:
                transform = readTransformStart(rec.payload, transform: transform)
            case .mag:
                if case .real8(let v) = rec.payload, let first = v.first {
                    transform = IRTransform(mirrorX: transform.mirrorX, magnification: first, angle: transform.angle)
                }
            case .angle:
                if case .real8(let v) = rec.payload, let first = v.first {
                    transform = IRTransform(mirrorX: transform.mirrorX, magnification: transform.magnification, angle: first)
                }
            case .xy:
                let pts = extractPoints(rec.payload)
                if let first = pts.first { position = first }
            case .string:
                if case .string(let s) = rec.payload { string = s }
            case .propattr:
                let prop = try readProperty(rec, r: &r)
                properties.append(prop)
            default:
                break
            }
        }

        return IRText(layer: layer, texttype: texttype, transform: transform, position: position, string: string, properties: properties)
    }

    private static func readBox(_ r: inout GDSRecordReader) throws -> IRBoundary {
        var layer: Int16 = 0
        var boxtype: Int16 = 0
        var points: [IRPoint] = []
        var properties: [IRProperty] = []

        while r.hasMore {
            let nextType = try r.peekRecordType()
            if nextType == .endel {
                _ = try r.readRecord()
                break
            }
            let rec = try r.readRecord()
            switch rec.recordType {
            case .layer:
                if case .int16(let v) = rec.payload, let first = v.first { layer = first }
            case .boxtype:
                if case .int16(let v) = rec.payload, let first = v.first { boxtype = first }
            case .xy:
                points.append(contentsOf: extractPoints(rec.payload))
            case .propattr:
                let prop = try readProperty(rec, r: &r)
                properties.append(prop)
            default:
                break
            }
        }

        // BOX uses boxtype in the datatype field (like KLayout "as rectangles" mode)
        return IRBoundary(layer: layer, datatype: boxtype, points: points, properties: properties)
    }

    // MARK: - Helpers

    private static func extractPoints(_ payload: GDSRecordPayload) -> [IRPoint] {
        guard case .int32(let values) = payload else { return [] }
        var points: [IRPoint] = []
        points.reserveCapacity(values.count / 2)
        var i = 0
        while i + 1 < values.count {
            points.append(IRPoint(x: values[i], y: values[i + 1]))
            i += 2
        }
        return points
    }

    private static func readTransformStart(_ payload: GDSRecordPayload, transform: IRTransform) -> IRTransform {
        guard case .bitArray(let bits) = payload else { return transform }
        let mirrorX = (bits & 0x8000) != 0
        return IRTransform(mirrorX: mirrorX, magnification: transform.magnification, angle: transform.angle)
    }

    private static func readProperty(_ propAttrRec: GDSRecord, r: inout GDSRecordReader) throws -> IRProperty {
        var attribute: Int16 = 0
        if case .int16(let v) = propAttrRec.payload, let first = v.first {
            attribute = first
        }
        let valueRec = try r.readRecord()
        var value = ""
        if case .string(let s) = valueRec.payload {
            value = s
        }
        return IRProperty(attribute: attribute, value: value)
    }

    private static func skipToEndel(_ r: inout GDSRecordReader) throws {
        while r.hasMore {
            let rec = try r.readRecord()
            if rec.recordType == .endel { break }
        }
    }
}
