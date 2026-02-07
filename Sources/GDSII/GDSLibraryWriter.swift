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
        w.writeString(.libname, value: library.name)

        // UNITS: userUnitsPerDBU, metersPerDBU
        w.writeReal8(.units, values: [
            library.units.userUnitsPerDBU,
            library.units.metersPerDBU,
        ])

        // Structures (cells)
        for cell in library.cells {
            writeCell(&w, cell)
        }

        // ENDLIB
        w.writeNoData(.endlib)

        return w.data
    }

    // MARK: - Cell

    private static func writeCell(_ w: inout GDSRecordWriter, _ cell: IRCell) {
        let ts = currentTimestamp()
        w.writeInt16(.bgnstr, values: ts + ts)
        w.writeString(.strname, value: cell.name)

        for element in cell.elements {
            writeElement(&w, element)
        }

        w.writeNoData(.endstr)
    }

    // MARK: - Elements

    private static func writeElement(_ w: inout GDSRecordWriter, _ element: IRElement) {
        switch element {
        case .boundary(let b):
            writeBoundary(&w, b)
        case .path(let p):
            writePath(&w, p)
        case .cellRef(let r):
            writeCellRef(&w, r)
        case .arrayRef(let a):
            writeArrayRef(&w, a)
        case .text(let t):
            writeText(&w, t)
        }
    }

    private static func writeBoundary(_ w: inout GDSRecordWriter, _ b: IRBoundary) {
        w.writeNoData(.boundary)
        w.writeInt16(.layer, values: [b.layer])
        w.writeInt16(.datatype, values: [b.datatype])
        w.writeXY(b.points)
        writeProperties(&w, b.properties)
        w.writeNoData(.endel)
    }

    private static func writePath(_ w: inout GDSRecordWriter, _ p: IRPath) {
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
        writeProperties(&w, p.properties)
        w.writeNoData(.endel)
    }

    private static func writeCellRef(_ w: inout GDSRecordWriter, _ r: IRCellRef) {
        w.writeNoData(.sref)
        w.writeString(.sname, value: r.cellName)
        writeTransform(&w, r.transform)
        w.writeXY([r.origin])
        writeProperties(&w, r.properties)
        w.writeNoData(.endel)
    }

    private static func writeArrayRef(_ w: inout GDSRecordWriter, _ a: IRArrayRef) {
        w.writeNoData(.aref)
        w.writeString(.sname, value: a.cellName)
        writeTransform(&w, a.transform)
        w.writeInt16(.colrow, values: [a.columns, a.rows])
        w.writeXY(a.referencePoints)
        writeProperties(&w, a.properties)
        w.writeNoData(.endel)
    }

    private static func writeText(_ w: inout GDSRecordWriter, _ t: IRText) {
        w.writeNoData(.text)
        w.writeInt16(.layer, values: [t.layer])
        w.writeInt16(.texttype, values: [t.texttype])
        writeTransform(&w, t.transform)
        w.writeXY([t.position])
        w.writeString(.string, value: t.string)
        writeProperties(&w, t.properties)
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

    private static func writeProperties(_ w: inout GDSRecordWriter, _ props: [IRProperty]) {
        for prop in props {
            w.writeInt16(.propattr, values: [prop.attribute])
            w.writeString(.propvalue, value: prop.value)
        }
    }

    // MARK: - Timestamp

    private static func currentTimestamp() -> [Int16] {
        // Return a fixed timestamp for deterministic output
        // Year, Month, Day, Hour, Minute, Second
        return [2026, 1, 1, 0, 0, 0]
    }
}
