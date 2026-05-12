import Foundation
import LayoutIR

/// Converts an IRLibrary to GDSII binary data.
public enum GDSLibraryWriter {

    public static func write(_ library: IRLibrary) throws -> Data {
        var w = GDSRecordWriter()

        // HEADER
        w.writeInt16(.header, values: [600])

        // BGNLIB (creation + modification timestamps, 12 int16s)
        let ts = currentTimestamp()
        w.writeInt16(.bgnlib, values: ts + ts)

        // LIBNAME
        try w.writeString(.libname, value: library.name)

        // UNITS: userUnitsPerDBU, metersPerDBU
        w.writeReal8(.units, values: [
            library.units.userUnitsPerDBU,
            library.units.metersPerDBU,
        ])

        // Structures (cells)
        for cell in library.cells {
            try writeCell(&w, cell)
        }

        // ENDLIB
        w.writeNoData(.endlib)

        return w.data
    }

    // MARK: - Cell

    private static func writeCell(_ w: inout GDSRecordWriter, _ cell: IRCell) throws {
        let ts = currentTimestamp()
        w.writeInt16(.bgnstr, values: ts + ts)
        try w.writeString(.strname, value: cell.name)

        for element in cell.elements {
            try writeElement(&w, element)
        }

        w.writeNoData(.endstr)
    }

    // MARK: - Elements

    private static func writeElement(_ w: inout GDSRecordWriter, _ element: IRElement) throws {
        switch element {
        case .boundary(let b):
            try writeBoundary(&w, b)
        case .path(let p):
            try writePath(&w, p)
        case .cellRef(let r):
            try writeCellRef(&w, r)
        case .arrayRef(let a):
            try writeArrayRef(&w, a)
        case .text(let t):
            try writeText(&w, t)
        }
    }

    private static func writeBoundary(_ w: inout GDSRecordWriter, _ b: IRBoundary) throws {
        w.writeNoData(.boundary)
        w.writeInt16(.layer, values: [b.layer])
        w.writeInt16(.datatype, values: [b.datatype])
        w.writeXY(b.points)
        try writeProperties(&w, b.properties)
        w.writeNoData(.endel)
    }

    private static func writePath(_ w: inout GDSRecordWriter, _ p: IRPath) throws {
        w.writeNoData(.path)
        w.writeInt16(.layer, values: [p.layer])
        w.writeInt16(.datatype, values: [p.datatype])
        if p.pathType != .flush {
            w.writeInt16(.pathtype, values: [p.pathType.rawValue])
        }
        if p.width != 0 {
            w.writeInt32(.width, values: [p.width])
        }
        if let bext = p.beginExtension {
            w.writeInt32(.bgnextn, values: [bext])
        }
        if let eext = p.endExtension {
            w.writeInt32(.endextn, values: [eext])
        }
        w.writeXY(p.points)
        try writeProperties(&w, p.properties)
        w.writeNoData(.endel)
    }

    private static func writeCellRef(_ w: inout GDSRecordWriter, _ r: IRCellRef) throws {
        w.writeNoData(.sref)
        try w.writeString(.sname, value: r.cellName)
        writeTransform(&w, r.transform)
        w.writeXY([r.origin])
        try writeProperties(&w, r.properties)
        w.writeNoData(.endel)
    }

    private static func writeArrayRef(_ w: inout GDSRecordWriter, _ a: IRArrayRef) throws {
        w.writeNoData(.aref)
        try w.writeString(.sname, value: a.cellName)
        writeTransform(&w, a.transform)
        w.writeInt16(.colrow, values: [a.columns, a.rows])
        w.writeXY(a.referencePoints)
        try writeProperties(&w, a.properties)
        w.writeNoData(.endel)
    }

    private static func writeText(_ w: inout GDSRecordWriter, _ t: IRText) throws {
        w.writeNoData(.text)
        w.writeInt16(.layer, values: [t.layer])
        w.writeInt16(.texttype, values: [t.texttype])
        writeTransform(&w, t.transform)
        w.writeXY([t.position])
        try w.writeString(.string, value: t.string)
        try writeProperties(&w, t.properties)
        w.writeNoData(.endel)
    }

    // MARK: - Transform

    private static func writeTransform(_ w: inout GDSRecordWriter, _ t: IRTransform) {
        let hasTransform = t.mirrorX || t.magnification != 1.0 || t.angle != 0.0
        guard hasTransform else { return }

        var bits: UInt16 = 0
        if t.mirrorX { bits |= 0x8000 }
        w.writeBitArray(.strans, value: bits)

        if t.magnification != 1.0 {
            w.writeReal8(.mag, values: [t.magnification])
        }
        if t.angle != 0.0 {
            w.writeReal8(.angle, values: [t.angle])
        }
    }

    // MARK: - Properties

    private static func writeProperties(_ w: inout GDSRecordWriter, _ props: [IRProperty]) throws {
        for prop in props {
            w.writeInt16(.propattr, values: [prop.attribute])
            try w.writeString(.propvalue, value: prop.value)
        }
    }

    // MARK: - Timestamp

    private static func currentTimestamp() -> [Int16] {
        // Return a fixed timestamp for deterministic output
        // Year, Month, Day, Hour, Minute, Second
        return [2026, 1, 1, 0, 0, 0]
    }
}
