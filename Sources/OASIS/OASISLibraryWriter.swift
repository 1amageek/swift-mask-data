import Foundation
import LayoutIR

/// Converts an IRLibrary to OASIS binary data.
public enum OASISLibraryWriter {

    public static func write(_ library: IRLibrary) throws -> Data {
        var w = OASISWriter()

        // Magic
        w.writeMagic()

        // START record (record type 1)
        writeStartRecord(&w, library: library)

        // CELLNAME records (name table)
        var cellNameTable: [String: UInt64] = [:]
        for (index, cell) in library.cells.enumerated() {
            cellNameTable[cell.name] = UInt64(index)
            // CELLNAME record (record type 3): implicit reference number
            w.writeByte(OASISRecordType.cellname.rawValue)
            w.writeAString(cell.name)
        }

        // CELL records
        for cell in library.cells {
            writeCell(&w, cell, cellNameTable: cellNameTable)
        }

        // END record (record type 2)
        writeEndRecord(&w)

        return w.data
    }

    // MARK: - START

    private static func writeStartRecord(_ w: inout OASISWriter, library: IRLibrary) {
        w.writeByte(OASISRecordType.start.rawValue)
        w.writeAString("1.0") // version
        // unit: dbuPerMicron as real (1 micron = dbuPerMicron database units)
        // OASIS unit is the database unit size in microns = 1/dbuPerMicron
        let unitInMicrons = 1.0 / library.units.dbuPerMicron
        w.writeReal(unitInMicrons)
        // offset-flag: 0 = no offset tables
        w.writeUnsignedInteger(0)

        // Store library name as PROPSTRING (record type 9) for round-trip
        w.writeByte(OASISRecordType.propstring.rawValue)
        w.writeAString(library.name)
    }

    // MARK: - END

    private static func writeEndRecord(_ w: inout OASISWriter) {
        // Pad to ensure 256-byte aligned end (simplified: just write END + padding)
        w.writeByte(OASISRecordType.end.rawValue)
        // padding-string (empty)
        w.writeAString("")
        // validation-scheme = 0 (none)
        w.writeUnsignedInteger(0)
    }

    // MARK: - Cell

    private static func writeCell(_ w: inout OASISWriter, _ cell: IRCell, cellNameTable: [String: UInt64]) {
        // CELL record (record type 14): reference by number
        if let refNum = cellNameTable[cell.name] {
            w.writeByte(OASISRecordType.cellRef.rawValue)
            w.writeUnsignedInteger(refNum)
        } else {
            // Fallback: CELL by name (record type 13)
            w.writeByte(OASISRecordType.cell.rawValue)
            w.writeAString(cell.name)
        }

        for element in cell.elements {
            writeElement(&w, element, cellNameTable: cellNameTable)
        }
    }

    // MARK: - Elements

    private static func writeElement(_ w: inout OASISWriter, _ element: IRElement, cellNameTable: [String: UInt64]) {
        switch element {
        case .boundary(let b):
            writeBoundary(&w, b)
            writeProperties(&w, b.properties)
        case .path(let p):
            writePath(&w, p)
            writeProperties(&w, p.properties)
        case .cellRef(let r):
            writePlacement(&w, r, cellNameTable: cellNameTable)
            writeProperties(&w, r.properties)
        case .arrayRef(let a):
            writeArrayPlacement(&w, a, cellNameTable: cellNameTable)
            writeProperties(&w, a.properties)
        case .text(let t):
            writeText(&w, t)
            writeProperties(&w, t.properties)
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

    private static func writeBoundary(_ w: inout OASISWriter, _ b: IRBoundary) {
        // Check if axis-aligned rectangle → RECTANGLE record
        if let rect = isAxisAlignedRectangle(b.points) {
            // RECTANGLE (record type 20)
            w.writeByte(OASISRecordType.rectangle.rawValue)
            // info-byte: S W H X Y R D L
            // S=0 (no repetition), W=1, H=1, X=1, Y=1, R=0, D=1, L=1
            // Bit layout: S(7) W(6) H(5) X(4) Y(3) R(2) D(1) L(0)
            let infoByte: UInt8 = 0b0111_1011 // H, W, X, Y, D, L set
            w.writeByte(infoByte)
            w.writeUnsignedInteger(UInt64(max(0, b.layer)))    // L
            w.writeUnsignedInteger(UInt64(max(0, b.datatype)))  // D
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
        w.writeUnsignedInteger(UInt64(max(0, b.layer)))     // L
        w.writeUnsignedInteger(UInt64(max(0, b.datatype)))   // D

        // Convert absolute points to delta-encoded point list (excluding close point)
        let deltas = absoluteToDeltas(b.points)
        w.writePointList(deltas)

        // X, Y of first point
        w.writeSignedInteger(Int64(b.points[0].x))
        w.writeSignedInteger(Int64(b.points[0].y))
    }

    private static func writePath(_ w: inout OASISWriter, _ p: IRPath) {
        // PATH (record type 22)
        w.writeByte(OASISRecordType.path.rawValue)
        // info-byte: E X Y R D L W T
        // Bit layout: E(7) W(6) P(5) X(4) Y(3) R(2) D(1) L(0)
        var infoByte: UInt8 = 0b1011_1011 // E(7), P(5), X(4), Y(3), D(1), L(0) set
        infoByte |= 0b0100_0000 // W(6) set → 0b1111_1011
        w.writeByte(infoByte)
        w.writeUnsignedInteger(UInt64(max(0, p.layer)))     // L
        w.writeUnsignedInteger(UInt64(max(0, p.datatype)))   // D
        w.writeUnsignedInteger(UInt64(p.width / 2))  // half-width

        // Extension scheme: encode pathType
        let extScheme = oasisExtensionScheme(p.pathType)
        w.writeUnsignedInteger(extScheme)

        // Point list (deltas from first point)
        let deltas = absoluteToDeltas(p.points)
        w.writePointList(deltas)

        // X, Y of first point
        w.writeSignedInteger(Int64(p.points[0].x))
        w.writeSignedInteger(Int64(p.points[0].y))
    }

    private static func writeText(_ w: inout OASISWriter, _ t: IRText) {
        // TEXT (record type 19)
        w.writeByte(OASISRecordType.text.rawValue)
        // info-byte: C X Y R T L
        // Bit layout: C(6) N(5) X(4) Y(3) R(2) T(1) L(0)
        let infoByte: UInt8 = 0b0101_1011 // C(text-string), N=0, X, Y, T, L
        w.writeByte(infoByte)
        w.writeAString(t.string)     // C: inline text string
        w.writeUnsignedInteger(UInt64(max(0, t.layer)))    // L
        w.writeUnsignedInteger(UInt64(max(0, t.texttype)))  // T
        w.writeSignedInteger(Int64(t.position.x))   // X
        w.writeSignedInteger(Int64(t.position.y))   // Y
    }

    private static func writePlacement(_ w: inout OASISWriter, _ r: IRCellRef, cellNameTable: [String: UInt64]) {
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
            w.writeAString(r.cellName)

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
            w.writeAString(r.cellName)
            w.writeSignedInteger(Int64(r.origin.x))
            w.writeSignedInteger(Int64(r.origin.y))
        }
    }

    private static func writeArrayPlacement(_ w: inout OASISWriter, _ a: IRArrayRef, cellNameTable: [String: UInt64]) {
        // Convert AREF to PLACEMENT + repetition
        // Use simple PLACEMENT (record type 17) with grid repetition
        w.writeByte(OASISRecordType.placement.rawValue)
        // info-byte: C X Y R set
        let infoByte: UInt8 = 0b1011_1000 // C, X, Y, R
        w.writeByte(infoByte)
        w.writeAString(a.cellName)

        // Compute spacings from reference points
        let colSpacing: UInt64
        let rowSpacing: UInt64
        if a.referencePoints.count >= 3 && a.columns > 0 && a.rows > 0 {
            colSpacing = UInt64(abs(a.referencePoints[1].x - a.referencePoints[0].x) / Int32(a.columns))
            rowSpacing = UInt64(abs(a.referencePoints[2].y - a.referencePoints[0].y) / Int32(a.rows))
        } else {
            colSpacing = 0
            rowSpacing = 0
        }

        let rep = OASISRepetition.grid(
            columns: UInt64(a.columns),
            rows: UInt64(a.rows),
            colSpacing: colSpacing,
            rowSpacing: rowSpacing
        )

        w.writeSignedInteger(Int64(a.referencePoints[0].x))
        w.writeSignedInteger(Int64(a.referencePoints[0].y))
        w.writeRepetition(rep)
    }

    // MARK: - Helpers

    /// Convert absolute point sequence to delta-encoded (skip closing point for polygons).
    private static func absoluteToDeltas(_ points: [IRPoint]) -> [IRPoint] {
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
            let dx = effectivePoints[effectivePoints.startIndex + i].x - effectivePoints[effectivePoints.startIndex + i - 1].x
            let dy = effectivePoints[effectivePoints.startIndex + i].y - effectivePoints[effectivePoints.startIndex + i - 1].y
            deltas.append(IRPoint(x: dx, y: dy))
        }
        return deltas
    }

    /// Write PROPERTY records for an element's IR properties.
    private static func writeProperties(_ w: inout OASISWriter, _ properties: [IRProperty]) {
        for prop in properties {
            w.writeByte(OASISRecordType.property.rawValue)
            // info-byte: UUUU(7:4)=0001, V(3)=0, C(2)=1, T(1)=0 (inline name), S(0)=0
            let infoByte: UInt8 = (1 << 4) | 0x04  // = 0x14
            w.writeByte(infoByte)

            // Parse "key=value" format from IRProperty
            let parts = prop.value.split(separator: "=", maxSplits: 1)
            let name = parts.count > 0 ? String(parts[0]) : "attr_\(prop.attribute)"
            let value = parts.count > 1 ? String(parts[1]) : prop.value

            w.writeAString(name)       // inline property name
            // Write 1 value: a-string (type 3)
            w.writeUnsignedInteger(3)  // property value type = a-string
            w.writeAString(value)
        }
    }

    /// Map IRPathType to OASIS extension scheme value.
    private static func oasisExtensionScheme(_ pathType: IRPathType) -> UInt64 {
        switch pathType {
        case .flush:
            return 0           // both ends flush (0b0000)
        case .halfWidthExtend:
            return 5           // both ends halfwidth (0b0101)
        case .round:
            return 5           // approximate as halfwidth (0b0101)
        case .customExtension:
            return 5           // approximate as halfwidth (0b0101)
        }
    }
}
