import Foundation
import CircuiteFoundation
import LayoutIR

/// Converts an IRLibrary to OASIS binary data.
public enum OASISLibraryWriter {

    public static func write(_ library: IRLibrary) throws -> Data {
        var w = OASISWriter()
        let scale = library.databaseUnitScale

        // Magic
        w.writeMagic()

        // START record (record type 1)
        try writeStartRecord(&w, library: library, scale: scale)

        // CELLNAME records (name table)
        var cellNameTable: [String: UInt64] = [:]
        for (index, cell) in library.cells.enumerated() {
            cellNameTable[cell.name] = UInt64(index)
            // CELLNAME record (record type 3): implicit reference number
            w.writeByte(OASISRecordType.cellname.rawValue)
            try w.writeAString(cell.name)
        }

        // CELL records
        for cell in library.cells {
            try writeCell(&w, cell, cellNameTable: cellNameTable)
        }

        // END record (record type 2)
        try writeEndRecord(&w)

        return w.data
    }

    // MARK: - START

    private static func writeStartRecord(
        _ w: inout OASISWriter,
        library: IRLibrary,
        scale: DatabaseUnitScale
    ) throws {
        w.writeByte(OASISRecordType.start.rawValue)
        try w.writeAString("1.0") // version
        // unit: dbuPerMicron as real (1 micron = dbuPerMicron database units)
        // OASIS unit is the database unit size in microns = 1/dbuPerMicron
        let unitInMicrons = 1.0 / scale.databaseUnitsPerMicrometer
        w.writeReal(unitInMicrons)
        // offset-flag: 0 = no offset tables
        w.writeUnsignedInteger(0)

        // Store library name as PROPSTRING (record type 9) for round-trip
        w.writeByte(OASISRecordType.propstring.rawValue)
        try w.writeAString(library.name)
    }

    // MARK: - END

    private static func writeEndRecord(_ w: inout OASISWriter) throws {
        // Pad to ensure 256-byte aligned end (simplified: just write END + padding)
        w.writeByte(OASISRecordType.end.rawValue)
        // padding-string (empty)
        try w.writeAString("")
        // validation-scheme = 0 (none)
        w.writeUnsignedInteger(0)
    }

    // MARK: - Cell

    private static func writeCell(_ w: inout OASISWriter, _ cell: IRCell, cellNameTable: [String: UInt64]) throws {
        // CELL record (record type 14): reference by number
        if let refNum = cellNameTable[cell.name] {
            w.writeByte(OASISRecordType.cellRef.rawValue)
            w.writeUnsignedInteger(refNum)
        } else {
            // Fallback: CELL by name (record type 13)
            w.writeByte(OASISRecordType.cell.rawValue)
            try w.writeAString(cell.name)
        }

        for element in cell.elements {
            try writeElement(&w, element, cellNameTable: cellNameTable)
        }
    }

    // MARK: - Elements

    private static func writeElement(_ w: inout OASISWriter, _ element: IRElement, cellNameTable: [String: UInt64]) throws {
        switch element {
        case .boundary(let b):
            try writeBoundary(&w, b)
            try writeProperties(&w, b.properties)
        case .path(let p):
            try writePath(&w, p)
            try writeProperties(&w, p.properties)
        case .cellRef(let r):
            try writePlacement(&w, r, cellNameTable: cellNameTable)
            try writeProperties(&w, r.properties)
        case .arrayRef(let a):
            try writeArrayPlacement(&w, a, cellNameTable: cellNameTable)
            try writeProperties(&w, a.properties)
        case .text(let t):
            try writeText(&w, t)
            try writeProperties(&w, t.properties)
        }
    }

    private static func isAxisAlignedRectangle(_ points: [IRPoint]) -> (x: Int32, y: Int32, w: Int32, h: Int32)? {
        guard points.count == 5, points[0] == points[4] else { return nil }
        let xs = points[0...3].map(\.x)
        let ys = points[0...3].map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        // Check all points are corners of the bounding box
        for i in 0..<4 {
            let p = points[i]
            guard (p.x == minX || p.x == maxX) && (p.y == minY || p.y == maxY) else {
                return nil
            }
        }
        return (minX, minY, maxX - minX, maxY - minY)
    }

    private static func writeBoundary(_ w: inout OASISWriter, _ b: IRBoundary) throws {
        try validateBoundaryForLosslessOASISExport(b)
        // Check if axis-aligned rectangle → RECTANGLE record
        if let rect = isAxisAlignedRectangle(b.points) {
            // RECTANGLE (record type 20)
            w.writeByte(OASISRecordType.rectangle.rawValue)
            // info-byte: S W H X Y R D L
            // S=0 (no repetition), W=1, H=1, X=1, Y=1, R=0, D=1, L=1
            // Bit layout: S(7) W(6) H(5) X(4) Y(3) R(2) D(1) L(0)
            let infoByte: UInt8 = 0b0111_1011 // H, W, X, Y, D, L set
            w.writeByte(infoByte)
            try writeUnsignedLayerValue(&w, field: "layer", value: b.layer)
            try writeUnsignedLayerValue(&w, field: "datatype", value: b.datatype)
            w.writeUnsignedInteger(UInt64(rect.w))      // W
            w.writeUnsignedInteger(UInt64(rect.h))      // H
            w.writeSignedInteger(Int64(rect.x))         // X
            w.writeSignedInteger(Int64(rect.y))         // Y
            return
        }

        // POLYGON (record type 21)
        w.writeByte(OASISRecordType.polygon.rawValue)
        // info-byte: P X Y R D L
        // P=1, X=1, Y=1, R=0, D=1, L=1
        // Bit layout: P(5) X(4) Y(3) R(2) D(1) L(0)
        let infoByte: UInt8 = 0b0011_1011 // P, X, Y, D, L set
        w.writeByte(infoByte)
        try writeUnsignedLayerValue(&w, field: "layer", value: b.layer)
        try writeUnsignedLayerValue(&w, field: "datatype", value: b.datatype)

        // Convert absolute points to delta-encoded point list (excluding close point)
        let deltas = try absoluteToDeltas(b.points, context: "boundary")
        w.writePointList(deltas)

        // X, Y of first point
        w.writeSignedInteger(Int64(b.points[0].x))
        w.writeSignedInteger(Int64(b.points[0].y))
    }

    private static func writePath(_ w: inout OASISWriter, _ p: IRPath) throws {
        try validatePathForLosslessOASISExport(p)
        // PATH (record type 22)
        w.writeByte(OASISRecordType.path.rawValue)
        // info-byte: E X Y R D L W T
        // Bit layout: E(7) W(6) P(5) X(4) Y(3) R(2) D(1) L(0)
        var infoByte: UInt8 = 0b1011_1011 // E(7), P(5), X(4), Y(3), D(1), L(0) set
        infoByte |= 0b0100_0000 // W(6) set → 0b1111_1011
        w.writeByte(infoByte)
        try writeUnsignedLayerValue(&w, field: "layer", value: p.layer)
        try writeUnsignedLayerValue(&w, field: "datatype", value: p.datatype)
        w.writeUnsignedInteger(UInt64(p.width / 2))  // half-width

        // Extension scheme: encode pathType
        let extScheme = try oasisExtensionScheme(p.pathType)
        w.writeUnsignedInteger(extScheme)

        // Point list (deltas from first point)
        let deltas = try absoluteToDeltas(p.points, context: "path")
        w.writePointList(deltas)

        // X, Y of first point
        w.writeSignedInteger(Int64(p.points[0].x))
        w.writeSignedInteger(Int64(p.points[0].y))
    }

    private static func validatePathForLosslessOASISExport(_ path: IRPath) throws {
        guard path.points.count >= 2 else {
            throw OASISError.unsupportedGeometry(
                context: "path",
                reason: "OASIS PATH export requires at least two points."
            )
        }
        guard path.width > 0 else {
            throw OASISError.unsupportedGeometry(
                context: "path",
                reason: "OASIS PATH export requires a positive width."
            )
        }
        guard path.width % 2 == 0 else {
            throw OASISError.unsupportedGeometry(
                context: "path",
                reason: "OASIS PATH stores half-width; odd database-unit width \(path.width) cannot be exported without rounding."
            )
        }
    }

    private static func validateBoundaryForLosslessOASISExport(_ boundary: IRBoundary) throws {
        guard boundary.points.count >= 4 else {
            throw OASISError.unsupportedGeometry(
                context: "boundary",
                reason: "OASIS boundary export requires at least three vertices plus a closing point."
            )
        }
        guard boundary.points.first == boundary.points.last else {
            throw OASISError.unsupportedGeometry(
                context: "boundary",
                reason: "OASIS boundary export requires a closed polygon."
            )
        }
        let area2 = signedDoubleArea(boundary.points)
        guard area2 != 0 else {
            throw OASISError.unsupportedGeometry(
                context: "boundary",
                reason: "OASIS boundary export requires non-zero polygon area."
            )
        }
    }

    private static func writeText(_ w: inout OASISWriter, _ t: IRText) throws {
        // TEXT (record type 19)
        w.writeByte(OASISRecordType.text.rawValue)
        // info-byte: C X Y R T L
        // Bit layout: C(6) N(5) X(4) Y(3) R(2) T(1) L(0)
        let infoByte: UInt8 = 0b0101_1011 // C(text-string), N=0, X, Y, T, L
        w.writeByte(infoByte)
        try w.writeAString(t.string)     // C: inline text string
        try writeUnsignedLayerValue(&w, field: "layer", value: t.layer)
        try writeUnsignedLayerValue(&w, field: "texttype", value: t.texttype)
        w.writeSignedInteger(Int64(t.position.x))   // X
        w.writeSignedInteger(Int64(t.position.y))   // Y
    }

    private static func writeUnsignedLayerValue(_ w: inout OASISWriter, field: String, value: Int16) throws {
        guard value >= 0 else {
            throw OASISError.negativeLayerValue(field: field, value: value)
        }
        w.writeUnsignedInteger(UInt64(value))
    }

    private static func writePlacement(_ w: inout OASISWriter, _ r: IRCellRef, cellNameTable: [String: UInt64]) throws {
        let hasTransform = r.transform.mirrorX || r.transform.magnification != 1.0 || r.transform.angle != 0.0

        if hasTransform {
            // PLACEMENT with transform (record type 18)
            w.writeByte(OASISRecordType.placementT.rawValue)
            // info-byte: C X Y R F M A
            // Bit layout: C(7) N(6) X(5) Y(4) R(3) M(2) A(1) F(0)
            var infoByte: UInt8 = 0b1011_0000 // C, X, Y
            if r.transform.magnification != 1.0 { infoByte |= 0b0000_0100 } // M
            if r.transform.angle != 0.0 { infoByte |= 0b0000_0010 } // A
            if r.transform.mirrorX { infoByte |= 0b0000_0001 } // F (flip)
            w.writeByte(infoByte)

            // Cell reference (inline name)
            try w.writeAString(r.cellName)

            if r.transform.magnification != 1.0 {
                w.writeReal(r.transform.magnification)
            }
            if r.transform.angle != 0.0 {
                w.writeReal(r.transform.angle)
            }

            w.writeSignedInteger(Int64(r.origin.x))
            w.writeSignedInteger(Int64(r.origin.y))
        } else {
            // PLACEMENT without transform (record type 17)
            w.writeByte(OASISRecordType.placement.rawValue)
            // info-byte: C X Y R
            // Bit layout: C(7) N(6) X(5) Y(4) R(3) 0 0 0
            let infoByte: UInt8 = 0b1011_0000 // C, X, Y
            w.writeByte(infoByte)
            try w.writeAString(r.cellName)
            w.writeSignedInteger(Int64(r.origin.x))
            w.writeSignedInteger(Int64(r.origin.y))
        }
    }

    private static func writeArrayPlacement(_ w: inout OASISWriter, _ a: IRArrayRef, cellNameTable: [String: UInt64]) throws {
        guard a.columns > 0, a.rows > 0, a.referencePoints.count >= 3 else {
            throw OASISError.numericOverflow(
                context: "array placement repetition",
                value: "\(a.columns)x\(a.rows)"
            )
        }

        if a.columns == 1 && a.rows == 1 {
            try writePlacement(&w, IRCellRef(
                cellName: a.cellName,
                origin: a.referencePoints[0],
                transform: a.transform,
                properties: a.properties
            ), cellNameTable: cellNameTable)
            return
        }

        let hasTransform = a.transform.mirrorX
            || a.transform.magnification != 1.0
            || a.transform.angle != 0.0

        // Convert AREF to PLACEMENT + repetition.
        w.writeByte(hasTransform ? OASISRecordType.placementT.rawValue : OASISRecordType.placement.rawValue)
        // info-byte: C X Y R plus optional transform fields.
        var infoByte: UInt8 = 0b1011_1000 // C, X, Y, R
        if hasTransform {
            if a.transform.magnification != 1.0 { infoByte |= 0b0000_0100 }
            if a.transform.angle != 0.0 { infoByte |= 0b0000_0010 }
            if a.transform.mirrorX { infoByte |= 0b0000_0001 }
        }
        w.writeByte(infoByte)
        try w.writeAString(a.cellName)

        if hasTransform {
            if a.transform.magnification != 1.0 {
                w.writeReal(a.transform.magnification)
            }
            if a.transform.angle != 0.0 {
                w.writeReal(a.transform.angle)
            }
        }

        let origin = a.referencePoints[0]
        let colStep = try arrayStep(
            from: origin,
            to: a.referencePoints[1],
            count: Int64(a.columns),
            axis: "column"
        )
        let rowStep = try arrayStep(
            from: origin,
            to: a.referencePoints[2],
            count: Int64(a.rows),
            axis: "row"
        )
        let rep = repetitionForArray(
            columns: UInt64(a.columns),
            rows: UInt64(a.rows),
            colStep: colStep,
            rowStep: rowStep
        )

        w.writeSignedInteger(Int64(origin.x))
        w.writeSignedInteger(Int64(origin.y))
        w.writeRepetition(rep)
    }

    private static func arrayStep(
        from origin: IRPoint,
        to endpoint: IRPoint,
        count: Int64,
        axis: String
    ) throws -> OASISDisplacement {
        let dx = Int64(endpoint.x) - Int64(origin.x)
        let dy = Int64(endpoint.y) - Int64(origin.y)
        guard dx % count == 0, dy % count == 0 else {
            throw OASISError.unsupportedGeometry(
                context: "array placement repetition",
                reason: "OASIS array \(axis) reference vector cannot be represented as an integral database-unit step."
            )
        }
        return OASISDisplacement(dx: dx / count, dy: dy / count)
    }

    private static func repetitionForArray(
        columns: UInt64,
        rows: UInt64,
        colStep: OASISDisplacement,
        rowStep: OASISDisplacement
    ) -> OASISRepetition {
        if rows == 1 {
            if colStep.dy == 0 && colStep.dx >= 0 {
                return .uniformRow(count: columns, spacing: UInt64(colStep.dx))
            }
            return .variableDisplacementRow(
                displacements: Array(repeating: colStep, count: Int(columns - 1))
            )
        }
        if columns == 1 {
            if rowStep.dx == 0 && rowStep.dy >= 0 {
                return .uniformColumn(count: rows, spacing: UInt64(rowStep.dy))
            }
            return .variableDisplacementColumn(
                displacements: Array(repeating: rowStep, count: Int(rows - 1))
            )
        }
        if colStep.dy == 0 && rowStep.dx == 0 && colStep.dx >= 0 && rowStep.dy >= 0 {
            return .grid(
                columns: columns,
                rows: rows,
                colSpacing: UInt64(colStep.dx),
                rowSpacing: UInt64(rowStep.dy)
            )
        }
        return .arbitraryGrid(
            columns: columns,
            rows: rows,
            colDisplacement: colStep,
            rowDisplacement: rowStep
        )
    }

    // MARK: - Helpers

    /// Convert absolute point sequence to delta-encoded (skip closing point for polygons).
    private static func absoluteToDeltas(_ points: [IRPoint], context: String) throws -> [IRPoint] {
        guard points.count > 1 else { return points }

        // For polygons, exclude the closing point (last == first)
        let effectivePoints: ArraySlice<IRPoint>
        if points.count >= 3 && points.first == points.last {
            effectivePoints = points[0..<(points.count - 1)]
        } else {
            effectivePoints = points[0..<points.count]
        }

        var deltas: [IRPoint] = []
        deltas.reserveCapacity(effectivePoints.count - 1)
        for i in 1..<effectivePoints.count {
            let current = effectivePoints[effectivePoints.startIndex + i]
            let previous = effectivePoints[effectivePoints.startIndex + i - 1]
            let dx = try checkedDelta(current.x, previous.x, context: context)
            let dy = try checkedDelta(current.y, previous.y, context: context)
            deltas.append(IRPoint(x: dx, y: dy))
        }
        return deltas
    }

    private static func checkedDelta(_ current: Int32, _ previous: Int32, context: String) throws -> Int32 {
        let delta = Int64(current) - Int64(previous)
        guard delta >= Int64(Int32.min), delta <= Int64(Int32.max) else {
            throw OASISError.numericOverflow(context: "\(context) point delta", value: String(delta))
        }
        return Int32(delta)
    }

    private static func signedDoubleArea(_ points: [IRPoint]) -> Int64 {
        var area: Int64 = 0
        for index in 0..<(points.count - 1) {
            let first = points[index]
            let second = points[index + 1]
            area += Int64(first.x) * Int64(second.y) - Int64(second.x) * Int64(first.y)
        }
        return area
    }

    /// Write PROPERTY records for an element's IR properties.
    private static func writeProperties(_ w: inout OASISWriter, _ properties: [IRProperty]) throws {
        for prop in properties {
            w.writeByte(OASISRecordType.property.rawValue)
            // info-byte: UUUU(7:4)=0001, V(3)=0, C(2)=1, T(1)=0 (inline name), S(0)=0
            let infoByte: UInt8 = (1 << 4) | 0x04  // = 0x14
            w.writeByte(infoByte)

            // Parse "key=value" format from IRProperty
            let parts = prop.value.split(separator: "=", maxSplits: 1)
            let name = parts.count > 0 ? String(parts[0]) : "attr_\(prop.attribute)"
            let value = parts.count > 1 ? String(parts[1]) : prop.value

            try w.writeAString(name)       // inline property name
            // Write 1 value: a-string (type 3)
            w.writeUnsignedInteger(3)  // property value type = a-string
            try w.writeAString(value)
        }
    }

    /// Map IRPathType to OASIS extension scheme value.
    private static func oasisExtensionScheme(_ pathType: IRPathType) throws -> UInt64 {
        switch pathType {
        case .flush:
            return 0           // both ends flush (0b0000)
        case .halfWidthExtend:
            return 5           // both ends halfwidth (0b0101)
        case .round:
            throw OASISError.unsupportedGeometry(
                context: "path",
                reason: "OASIS PATH round end caps are not represented by this writer without approximation."
            )
        case .customExtension:
            throw OASISError.unsupportedGeometry(
                context: "path",
                reason: "OASIS PATH custom extensions are not represented by this writer without approximation."
            )
        }
    }
}
